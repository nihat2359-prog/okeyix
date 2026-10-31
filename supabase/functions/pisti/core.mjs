import {rank, shuffledDeck, secureInt} from './cards.mjs';
export const points = id => rank(id) === 1 || rank(id) === 11 ? 1 : id === 1 ? 2 : id === 22 ? 3 : 0;

export const RULES = 'okeyix-pisti-101-v1';
const other = seat => 1 - seat;
function requireThat(value, code) { if (!value) throw new Error(code); }
export function newMatch({target = 101, dealer = secureInt(2), randomInt = secureInt} = {}) {
  requireThat(Number.isInteger(target) && target >= 1 && target <= 1001, 'INVALID_TARGET');
  const state = {rules: RULES, target, dealer, round: 0, total: [0,0],
    pistiTotal: [0,0], rounds: [], status: 'playing', winner: null, reason: null, seq: 0};
  return startRound(state, randomInt);
}
function startRound(s, randomInt) {
  s.round++;
  s.deck = shuffledDeck(randomInt);
  s.pile = s.deck.splice(-4);
  // Rotate initial jacks below the first non-jack. All-jack centre is redealt.
  if (s.pile.every(c => rank(c) === 11)) return startRound({...s, round:s.round-1}, randomInt);
  while (rank(s.pile.at(-1)) === 11) s.pile.unshift(s.pile.pop());
  s.hands = [[],[]]; s.won = [[],[]]; s.bonus = [0,0]; s.pistis = [0,0];
  s.lastCollector = null; s.played = 0; s.deal = 0; s.turn = other(s.dealer);
  deal(s);
  return s;
}
function deal(s) {
  for (let n=0; n<4; n++) for (const seat of [other(s.dealer),s.dealer]) s.hands[seat].push(s.deck.pop());
  s.deal++;
}
export function roundScore(s) {
  return [0,1].map(seat => s.won[seat].reduce((n,c) => n+points(c), 0) + s.bonus[seat] +
    (s.won[seat].length > s.won[other(seat)].length ? 3 : 0));
}
export function play(state, seat, card, randomInt = secureInt) {
  const s = structuredClone(state);
  requireThat(s.status === 'playing', 'MATCH_FINISHED');
  requireThat(seat === s.turn, 'NOT_YOUR_TURN');
  requireThat(Number.isInteger(card) && s.hands[seat].includes(card), 'CARD_NOT_OWNED');
  const top = s.pile.at(-1);
  const matches = top !== undefined && rank(top) === rank(card);
  const captures = top !== undefined && (matches || rank(card) === 11);
  const bonus = captures && matches && s.pile.length === 1 && s.played > 0 && s.played < 47
    ? (rank(card) === 11 ? 20 : 10) : 0;
  const taken = captures ? [...s.pile, card] : [];
  s.hands[seat].splice(s.hands[seat].indexOf(card),1);
  s.pile.push(card); s.played++; s.seq++;
  if (captures) {
    s.won[seat].push(...s.pile); s.pile = []; s.lastCollector = seat;
    s.bonus[seat] += bonus;
    if (bonus) { s.pistis[seat]++; s.pistiTotal[seat]++; }
  }
  // Only played cards are public. Initial face-down centre is never broadcast.
  s.event = {seq:s.seq, seat, card, captured: taken.length, bonus, round:s.round, deal:s.deal};
  s.turn = other(seat);
  if (s.hands.every(h => !h.length)) {
    if (s.deck.length) deal(s);
    else {
      const collector = s.lastCollector ?? s.dealer;
      s.event.sweep = s.pile.length;
      s.event.sweep_seat = collector;
      s.won[collector].push(...s.pile); s.pile=[];
      const score = roundScore(s);
      s.total = s.total.map((n,i) => n+score[i]);
      s.rounds.push({round:s.round, score, cards:s.won.map(c=>c.length), pistis:[...s.pistis]});
      if (Math.max(...s.total) >= s.target && s.total[0] !== s.total[1]) {
        s.status='finished'; s.winner=s.total[0]>s.total[1]?0:1; s.reason='normal';
      } else { s.dealer=other(s.dealer); startRound(s, randomInt); }
    }
  }
  return s;
}
// Bot receives only its hand and public top/count. Never accepts the full state.
export function botCard(hand, top, pileCount) {
  requireThat(hand.length, 'EMPTY_HAND');
  const matching=hand.find(c=>top != null && rank(c)===rank(top));
  if (matching !== undefined) return matching;
  const jack=hand.find(c=>rank(c)===11);
  if (pileCount && jack !== undefined) return jack;
  return [...hand].sort((a,b)=>(points(a)+(rank(a)===11?10:0))-(points(b)+(rank(b)===11?10:0)) || a-b)[0];
}
export function forfeit(state, loser, reason) {
  requireThat([0,1].includes(loser) && ['leave','timeout','disconnect','moderation'].includes(reason), 'INVALID_FORFEIT');
  requireThat(state.status==='playing','MATCH_FINISHED');
  return {...structuredClone(state), status:'finished', winner:other(loser), reason, seq:state.seq+1};
}
export function publicState(s, viewer = null) {
  // Settled totals stay authoritative. Show earned card/Pişti points immediately;
  // the majority bonus is awarded only when the round is settled.
  const score = s.total.map((n,i) => n + (s.status === 'playing'
    ? s.won[i].reduce((sum,card) => sum+points(card),0) + s.bonus[i] : 0));
  return {rules:s.rules,target:s.target,round:s.round,deal:s.deal,turn:s.turn,
    score,
    total:s.total,rounds:s.rounds,pistis:s.pistiTotal,status:s.status,winner:s.winner,reason:s.reason,
    seq:s.seq,deck_count:s.deck.length,pile_count:s.pile.length,top:s.pile.at(-1) ?? null,
    hand:viewer===0||viewer===1?s.hands[viewer]:[],hand_counts:s.hands.map(h=>h.length),
    won_counts:s.won.map(h=>h.length),event:s.event ?? null};
}
