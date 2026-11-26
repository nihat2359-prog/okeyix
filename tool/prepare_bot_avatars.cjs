const fs = require('fs');
const path = require('path');
const output = path.resolve('output/bot-avatars/v1');
fs.mkdirSync(output, {recursive: true});
const rows = fs.readFileSync('.dart_tool/bot-avatar-preflight.log', 'utf8')
  .split(/\r?\n/).filter(s => s.includes('NOTICE (00000): BOT_AVATAR '))
  .map(s => JSON.parse(s.slice(s.indexOf('BOT_AVATAR ') + 11)));
if (rows.length !== 164 || new Set(rows.map(x=>x.id)).size !== 164) throw Error('Expected 164 unique bots');
const female = new Set('merve zeynep elif selin ayşe ece ceren seda esra bahar pelin aylin özge gizem irem büşra tuğçe gamze'.split(' '));
const male = new Set('ahmet burak emre murat mustafa mehmet ali hasan hüseyin can kerem mert onur arda hakan serkan uğur fatih oğuz yusuf'.split(' '));
const maleScenes = [
  'adult man in a dark jacket, viewed entirely from behind at the Bosphorus waterfront',
  'adult man with short dark hair seen from behind on a wooded walking trail, green jacket',
  'adult man in a light linen shirt looking out over an Aegean harbor, rear three-quarter view, face hidden',
  'adult man with salt-and-pepper hair from behind, sitting on a seaside bench at dusk',
  'adult man wearing a simple hoodie, rear view looking toward a mountain lake',
  'adult man wearing a cap, seen from behind at an old town street cafe',
  'adult man in a checked shirt, rear view watching fishing boats in a small harbor',
  'adult man in a navy sweater viewed from behind on a misty hillside',
];
const femaleScenes = [
  'adult woman with shoulder-length dark hair in a beige coat, viewed entirely from behind at a seaside promenade',
  'adult woman with long brown hair in a denim jacket, rear view among autumn trees',
  'adult woman with curly dark hair in a sage linen shirt, seen from behind overlooking an Aegean harbor',
  'adult woman wearing a muted patterned headscarf and a light coat, entirely rear view at a garden wall',
  'adult woman with a loose dark ponytail, rear view sitting on a waterfront bench at dusk',
  'adult woman with short brown hair in a blue cardigan, viewed from behind at an old town street',
  'adult woman wearing a straw hat, rear view by a sunlit olive grove',
  'adult woman with wavy auburn hair wearing a dark jacket, rear view on a misty walking trail',
];
const animals = [
  'ginger tabby cat resting on a windowsill', 'black cat with amber eyes sitting by a doorway',
  'white-and-gray cat curled up on a knitted blanket', 'friendly golden retriever resting in a garden',
  'small blue budgerigar perched on a branch', 'white seagull at a seaside railing',
  'sleepy striped kitten sitting on a cushion', 'brown-and-white dog with gentle eyes in a park',
  'small robin on an olive branch', 'tortoiseshell cat stretching on a sunny stone step',
  'white cat with blue eyes near a garden window', 'gray rabbit in a patch of meadow grass',
];
const objects = [
  'Turkish tulip-shaped tea glass and saucer on a small seaside cafe table',
  'small white fishing boat with blue trim in an Aegean harbor',
  'vintage cream-colored scooter parked by a blue wooden door',
  'a peaceful turquoise sea cove framed by pine trees',
  'an old red car parked on a quiet coastal road, no visible logos or readable plates',
  'a wooden pier leading toward a still lake at dawn',
  'a worn leather-bound book and Turkish coffee cup by a window',
  'a lighthouse on a rocky coast beneath a cloudy sky',
  'a single ripe yellow lemon with green leaves on a rustic table',
  'rounded white pebbles beside rippling clear turquoise water',
  'an amber tea glass steaming on a rainy cafe windowsill',
  'a warm street lamp illuminating an old stone alley at blue hour',
];
const flowers = [
  'one white daisy with a yellow center against a deep sage green background',
  'a single burgundy rose against a softly blurred dark garden',
  'small purple lavender flowers against a warm cream wall',
  'a white jasmine branch against a desaturated blue background',
  'a pink geranium flowering beside a sunlit blue wooden window',
  'a single sunflower against a deep teal softly blurred background',
  'a sprig of olive leaves against a warm textured beige background',
  'delicate white wildflowers in a small glass vase near a window',
];
const counts = {};
const manifest = rows.map((row, i) => {
  const normalized = row.username.toLocaleLowerCase('tr-TR');
  const first = normalized.match(/[a-zçğıöşü]+/u)?.[0];
  let gender = female.has(first) ? 'female' : male.has(first) ? 'male' : 'neutral';
  if (normalized.includes('denizkızı') || normalized.includes('küçükhanım')) gender = 'female';
  if (/papatya|gülkurusu|kırçiçeği|akşamsefası|^yıldız$/.test(normalized)) gender = 'female';
  if (normalized.includes('sessizadam') || normalized.includes('kral')) gender = 'male';
  let category;
  if (gender !== 'neutral') category = i % 4 === 0 ? 'illustration' : 'photo';
  else if (normalized.includes('kedi') || normalized.includes('kuş')) category = 'animal';
  else if (/papatya|gülkurusu|kırçiçeği/.test(normalized)) category = 'flower';
  else category = ['animal','scene','scene','flower'][i%4];
  const key = gender + '-' + category;
  const variant = counts[key] || 0;
  counts[key] = variant + 1;
  let subject;
  if (category === 'photo') subject = (gender === 'female' ? femaleScenes : maleScenes)[variant % 8];
  if (category === 'illustration') subject = `original illustrated portrait of a fictional adult ${gender === 'female' ? 'woman' : 'man'}, ${['short dark hair','wavy brown hair','curly dark hair','straight dark hair'][variant%4]}, wearing ${['a teal scarf','an ochre jacket','a muted blue shirt','a burgundy sweater'][variant%4]}, expressive relaxed face, ${['ink and watercolor','textured gouache painting','soft colored pencil','matte hand-painted adventure character'][variant%4]}`;
  if (category === 'animal') subject = animals[variant%animals.length];
  if (category === 'scene') subject = objects[variant%objects.length];
  if (category === 'flower') subject = flowers[variant%flowers.length];
  if (gender === 'neutral' && normalized.includes('çay')) subject = objects[variant%2===0 ? 0 : 10];
  if (gender === 'neutral' && normalized.includes('sarılımon')) subject = objects[8];
  const prompt = `Use case: ${category==='illustration' ? 'illustration-story' : 'photorealistic-natural'}. Generate ONE square profile avatar image, full bleed to all edges, no frame or circular mask. Subject: ${subject}. ${category==='illustration' ? 'Original varied hand-drawn style, not a standard glossy 3D game avatar.' : 'Candid everyday smartphone photograph with natural realistic textures and modest photographic imperfections, not stock advertising or a studio portrait.'} Composition: one strong centered subject, easily readable at 48px, keep important details within center 70% for a circular profile crop. ${category==='photo' ? 'Adult person only, no children, preserve the specified gender, face hidden or viewed from behind; fictional person.' : ''} Lighting: ${['soft overcast daylight','warm late afternoon','gentle morning window light','subtle cloudy natural light','warm dusk light'][i%5]}. Distinct camera position and ${['muted warm colors','cool natural colors','earthy greens and browns','soft blue and amber tones','restrained natural contrast'][i%5]}. ${category==='scene'||category==='animal'||category==='flower' ? 'No people, no human portraits.' : ''} No text, watermark, username, logos, letters, border, UI, montage or contact sheet. One coherent individual image only. Image variation ${i+1}: ${['tight close framing','soft background depth','slightly offset subject within center','quiet natural background','simple strong silhouette'][i%5]}.`;
  return {id:row.id, username:row.username, previous_avatar:row.avatar_url, gender, category, prompt, file:`${row.id}.jpg`, storage_path:`profiles-v1/images/${row.id}.jpg`};
});
const manifestPath = path.join(output,'manifest.json');
const generatedPath = path.join(output,'generated.json');
if (fs.existsSync(manifestPath) && fs.existsSync(generatedPath)) {
  const previous = JSON.parse(fs.readFileSync(manifestPath,'utf8'));
  const generated = JSON.parse(fs.readFileSync(generatedPath,'utf8'));
  const valid = generated.filter(file => {
    const old = previous.find(p=>p.id===file.id);
    const next = manifest.find(p=>p.id===file.id);
    return old && next && old.gender===next.gender && old.category===next.category;
  });
  fs.writeFileSync(generatedPath,JSON.stringify(valid,null,2)+'\n');
}
fs.writeFileSync(path.join(output,'manifest.json'), JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({total:manifest.length,groups:counts}));
