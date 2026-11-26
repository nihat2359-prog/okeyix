const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const directory='output/avatar-presets-v2';
fs.mkdirSync(directory,{recursive:true});
const registry=fs.readFileSync('lib/ui/avatar_preset.dart','utf8');
const descriptions={
  kadin_01:'woman aged 26, long chestnut hair, black sunglasses, small silver earrings, elegant black blouse, relaxed confident smile',
  kadin_02:'woman aged 25, loose wavy dark-brown hair, warm smile, red casual blouse, warm olive complexion',
  kadin_03:'woman aged 30, shoulder-length wavy dark-brown hair, blue denim jacket over a cream top, open friendly smile',
  kadin_04:'mature woman aged 58, short blonde-gray bob, elegant thin glasses, ivory blazer, pearl necklace, expressive gentle smile and natural age lines',
  kadin_05:'woman aged 32 wearing a fully covering black hijab with absolutely no hair visible, dark tailored blouse, calm friendly expression',
  kadin_06:'woman aged 30, long dark hair tied loosely back, dark sunglasses, black modern leather jacket, tiny gold hoop earrings, confident expression',
  kadin_07:'woman aged 30 wearing a fully covering cream hijab with a subtle small botanical pattern, no hair visible, ivory blouse, gentle smile',
  kadin_08:'woman aged 35 wearing a fully covering muted burgundy patterned headscarf, no hair visible, modest burgundy blouse, understated traditional Anatolian embroidered trim, warm expression',
  kadin_09:'mature woman aged 55 wearing a fully covering brown floral headscarf, no hair visible, warm knitted cardigan, natural age lines, warm dignified smile',
  kadin_10:'woman aged 45, warm brown complexion, curly dark hair in a loose high bun, black blouse, subtle gold necklace, expressive adult features',
  kadin_11:'woman aged 28, long softly wavy blonde hair, cream blouse with small blue floral accents, friendly composed expression',
  kadin_12:'elderly Anatolian woman aged 67 wearing a fully covering muted olive patterned headscarf, no hair visible, traditional woven dark vest over a modest blouse, natural wrinkles, warm dignified expression',
  erkek_01:'man aged 25, short swept-up chestnut hair, clean-shaven, dark teal casual shirt, relaxed friendly smile',
  erkek_02:'man aged 31, medium-length wavy dark-brown hair, light stubble, charcoal leather jacket, confident relaxed smile',
  erkek_03:'man aged 34, short dark hair, neatly trimmed dark beard, black sunglasses, dark tailored suit and pale shirt, warm confident smile',
  erkek_04:'elderly man aged 68, swept-back silver hair, full neatly groomed white beard, textured brown turtleneck, natural wrinkles, warm dignified smile',
  erkek_05:'man aged 40 with a shaved bald head and prominent neat dark moustache, tan blazer and open-neck white shirt, lively warm expression',
  erkek_06:'man aged 45, dark side-parted hair and thick neat moustache, charcoal suit and navy tie, olive skin, composed self-assured expression',
  erkek_07:'man aged 28, dark shoulder-length hair, clean-shaven, charcoal hooded jacket with hood up, warm olive skin, calm focused expression',
  erkek_08:'older man aged 60 with dark brown skin, close-cropped salt-and-pepper hair and a neatly groomed gray beard, charcoal suit and warm gold tie, natural age lines, dignified warm expression',
  erkek_09:'man aged 42, short neatly styled dark hair, trimmed stubble, charcoal jacket and ivory shirt, subtle patterned tie, welcoming confident smile',
  erkek_10:'man aged 38 with medium brown skin, short curly dark hair, trimmed beard, charcoal suit and ivory shirt, modern composed friendly expression',
  erkek_11:'Anatolian man aged 48, dark wavy hair and thick moustache, loosely draped olive patterned traditional head wrap, ivory collarless shirt and textured dark vest, natural age lines, warm thoughtful expression',
  erkek_12:'Anatolian man aged 58, gray-brown flat cap, salt-and-pepper moustache, textured brown jacket and knitted waistcoat over an ivory shirt, natural age lines, warm friendly expression',
  premium_kadin_01:'woman aged 32 wearing a fully covering black hijab with no hair visible, refined black leather jacket, small gold earrings, elegant confident adult expression',
  premium_kadin_02:'woman aged 34, blonde hair in a loose swept-back updo, refined black sunglasses, dark leather jacket, delicate gold necklace, confident friendly adult expression',
  premium_kadin_03:'woman aged 30, shoulder-length vibrant auburn-red hair, refined burgundy leather jacket, small understated pendant necklace, confident friendly adult expression',
  premium_kadin_04:'woman aged 38 wearing a fully covering taupe hijab with no hair visible, elegant camel blazer over an ivory blouse, polished modest styling, warm confident adult expression',
  premium_erkek_01:'man aged 33, short swept-back chestnut hair, neatly groomed beard, tailored charcoal suit, ivory shirt and deep burgundy silk tie, warm confident adult expression',
  premium_erkek_02:'man aged 37, side-parted dark-brown hair, trimmed beard, tailored navy suit, pale blue shirt and blue striped tie, confident friendly adult expression',
  premium_erkek_03:'elderly man aged 68, swept-back silver hair and full neat silver beard, elegant slim blue glasses, tailored charcoal suit, white shirt and burgundy tie, natural wrinkles, warm dignified expression',
  premium_erkek_04:'elderly man aged 65, swept-back silver hair and neat silver beard, refined black sunglasses, premium charcoal leather jacket over a black shirt, mature natural age lines, confident warm expression',
};
const entries=[...registry.matchAll(/AvatarPreset\(\s*id: '([^']+)',\s*label: '([^']+)',\s*imageUrl: '([^']+)',\s*gender: '([^']+)'/g)]
  .filter(([,id])=>id!=='bot1'&&id!=='bot2')
  .map(([,id,label,target,gender])=>{
    if(!descriptions[id])throw Error(`Missing art direction for ${id}`);
    const premium=id.startsWith('premium_');
    const subject=descriptions[id];
    const prompt=`Create ONE original professional modern 2D illustrated mobile tabletop-game profile avatar. Subject: a fictional adult ${subject}. Style: elegant contemporary character illustration, confident clean contour shapes, controlled layered cel shading, restrained sophisticated color palette, subtly angular shadow planes, excellent anatomical drawing and distinct facial features. Clearly drawn 2D illustration, NOT a photograph, photorealistic render, glossy 3D toy or corporate icon. Real adult facial proportions, natural-sized eyes, appropriate age, no baby face. Head and upper shoulders, eye-level near-front three-quarter portrait, face large and centered, entire hairstyle or head covering comfortably inside center 80% circular crop safe area. Simple dark forest-green to muted teal softly graded backdrop, restrained warm champagne rim light, natural skin tones. ${premium?'Premium collection: refined material accents, rich charcoal and burgundy fabrics, subtle warm gold detail and especially polished dramatic lighting; no crown, frame or badge.':'Standard collection: warm clean approachable styling, refined but restrained detail.'} Same cohesive art direction as a premium illustrated Turkish okey game, distinct adult identity. Full square image to edges, no circle mask, border, ring, text, logo, watermark, symbols, UI or contact sheet. Bust portrait only, no hands. Readable at 48 pixels. ${subject.includes('no hair visible')?'Head covering must fully conceal all hair, respect the specified modest outfit.':''}`;
    const original=fs.readFileSync(target);
    return {id,label,target,gender,premium,subject,prompt,original_sha256:crypto.createHash('sha256').update(original).digest('hex'),original_bytes:original.length};
  });
if(entries.length!==32||new Set(entries.map(x=>x.target)).size!==32)throw Error('Expected 32 unique user presets');
const untouched_bot_assets=['assets/images/avatars/bot1.png','assets/images/avatars/bot2.png'].map(target=>({target,sha256:crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex')}));
const manifest={registry_sha256:crypto.createHash('sha256').update(registry).digest('hex'),untouched_bot_assets,entries};
fs.writeFileSync(path.join(directory,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({total:entries.length,standard:entries.filter(x=>!x.premium).length,premium:entries.filter(x=>x.premium).length,original_bytes:entries.reduce((n,x)=>n+x.original_bytes,0)}));
