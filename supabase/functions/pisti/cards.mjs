// Shared 52-card wire format: clubs, diamonds, hearts, spades; A=1, J=11.
export const rank = id => id % 13 + 1;
export function shuffledDeck(randomInt) {
  const cards = Array.from({length: 52}, (_, i) => i);
  for (let i = 51; i > 0; i--) {
    const j = randomInt(i + 1);
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}
export function secureInt(max) {
  const limit = 2 ** 32 - (2 ** 32 % max);
  const buffer = new Uint32Array(1);
  do { crypto.getRandomValues(buffer); } while (buffer[0] >= limit);
  return buffer[0] % max;
}
