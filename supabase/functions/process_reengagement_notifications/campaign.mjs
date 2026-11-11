// One-shot queue, five simultaneous FCM requests, durable results per group.
// SQL owns recipient selection, token deduplication and at-most-once dispatch.
export async function processCampaignBatch({ rpc, getAccessToken, send, now = Date.now }) {
  const preview = await rpc('preview');
  if (!preview.enabled || !preview.within_send_window || !(preview.pending > 0 || preview.recoverable > 0)) {
    return { mode: 'no_send', preview };
  }
  const accessToken = await getAccessToken();
  const deadline = now() + 45000;
  const counts = { reserved: 0, accepted: 0, rejected: 0, invalid_token: 0, unknown: 0 };
  for (let group = 0; group < 20 && now() < deadline; group++) {
    const claim = await rpc('claim_batch');
    if (!claim.items?.length) break;
    if (claim.items.length > 5 || !claim.batch_id || !claim.campaign_id) throw new Error('INVALID_CLAIM');
    counts.reserved += claim.items.length;
    const results = await Promise.all(claim.items.map(async (item) => {
      // An unexpected adapter error may still follow a successful external send.
      let result;
      try { result = await send(accessToken, item); }
      catch { result = { status: 'unknown', code: 'NETWORK_OUTCOME_UNKNOWN' }; }
      return { ...result, id: item.id };
    }));
    const finished = await rpc('finish_batch', claim.campaign_id, { batch_id: claim.batch_id, results });
    if (finished?.recorded !== true) throw new Error('RESULT_NOT_RECORDED');
    for (const result of results) counts[result.status]++;
    // Persist completed attempts, then stop on a provider-wide error. Unknown
    // outcomes are never resent; later schedules only claim untouched devices.
    if (results.some((result) => result.status === 'unknown' || [401, 403, 429].includes(result.http_status)
      || result.http_status >= 500 || result.code === 'INVALID_ARGUMENT')) break;
  }
  return { mode: 'campaign_processed', counts };
}
