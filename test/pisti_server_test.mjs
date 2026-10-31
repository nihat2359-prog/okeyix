import test from 'node:test';
import assert from 'node:assert/strict';
import {newMatch,play,botCard,forfeit,publicState,roundScore,points} from '../supabase/functions/pisti/core.mjs';
import {rank} from '../supabase/functions/pisti/cards.mjs';
const random=()=>{let seed=12;return max=>{seed=(seed*1664525+1013904223)>>>0;return seed%max;};};
function fixture({pile=[6],hand=[19],played=10,deck=[0],opponent=[3]}={}){
 const s=newMatch({dealer:1,randomInt:random()});
 return {...s,pile,hands:[hand,opponent],deck,won:[[],[]],turn:0,played};
}
test('52 unique cards, 4 centre/4 each, initial non-jack, six deals',()=>{
 for(let i=0;i<200;i++){
  let s=newMatch({dealer:i%2});
  const all=[...s.deck,...s.pile,...s.hands.flat()];assert.equal(new Set(all).size,52);assert.equal(s.deck.length,40);assert.notEqual(rank(s.pile.at(-1)),11);
  assert.equal(s.turn,1-s.dealer);
 }
});
test('all scoring cards total 13 plus majority 3; 26–26 no majority',()=>{
 const cards=Array.from({length:52},(_,i)=>i);assert.equal(cards.reduce((n,c)=>n+points(c),0),13);
 const s=fixture();s.won=[cards.slice(0,26),cards.slice(26)];assert.equal(roundScore(s).reduce((a,b)=>a+b),13);
 s.won=[cards.slice(0,27),cards.slice(27)];assert.equal(roundScore(s).reduce((a,b)=>a+b),16);
});
test('matching, jack capture, 10 and 20 pisti, first/last exceptions',()=>{
 assert.equal(play(fixture(),0,19).bonus[0],10);
 assert.equal(play(fixture({pile:[10],hand:[23]}),0,23).bonus[0],20);
 assert.equal(play(fixture({hand:[10]}),0,10).bonus[0],0);
 assert.equal(play(fixture({pile:[6,4],hand:[17]}),0,17).won[0].length,3);
 assert.equal(play(fixture({played:0}),0,19).bonus[0],0);
 assert.equal(play(fixture({played:47}),0,19).bonus[0],0);
});

test('live score includes earned Pişti and card points without early majority or double counting',()=>{
 const normal=play(fixture(),0,19);
 assert.deepEqual(publicState(normal,0).score,[10,0]);
 assert.deepEqual(normal.total,[0,0]);
 const jack=play(fixture({pile:[10],hand:[23]}),0,23);
 assert.deepEqual(publicState(jack,0).score,[22,0]);
 normal.total=[30,12];
 assert.deepEqual(publicState(normal,1).score,[40,12]);
 const settled={...normal,status:'finished',total:[43,12]};
 assert.deepEqual(publicState(settled,0).score,[43,12]);
 const nextRound={...normal,won:[[],[]],bonus:[0,0],total:[43,12]};
 assert.deepEqual(publicState(nextRound,0).score,[43,12]);
 assert.equal('won' in publicState(normal,0),false);
});
test('last sweep goes to last collector, fallback dealer, never a pisti',()=>{
 let s=fixture({pile:[4],hand:[1],played:47,deck:[],opponent:[]});s.lastCollector=1;
 let next=play(s,0,1,random());assert.equal(next.rounds[0].cards[1],2);assert.equal(next.rounds[0].pistis[0],0);
 s.lastCollector=null;next=play(s,0,1,random());assert.equal(next.rounds[0].cards[1],2);
});
test('server rejects wrong turn, non-owned card, finished match',()=>{
 const s=fixture();assert.throws(()=>play(s,1,3),/NOT_YOUR_TURN/);assert.throws(()=>play(s,0,50),/CARD_NOT_OWNED/);
 assert.throws(()=>play(forfeit(s,0,'leave'),0,19),/MATCH_FINISHED/);
});
test('private projection reveals only own hand and public counts/top',()=>{
 const s=newMatch({randomInt:random()});
 for(const viewer of [0,1,null,-1]){
  const p=publicState(s,viewer);assert.equal(p.hand.length,viewer===0||viewer===1?4:0);
  for(const key of ['hands','deck','pile','won','lastCollector'])assert.equal(key in p,false);
  assert.equal('taken' in (p.event??{}),false);
 }
});
test('full matches conserve cards, alternate dealer and terminate at unequal target',()=>{
 for(let n=0;n<40;n++){
  let s=newMatch({target:101,randomInt:random()});let moves=0,previousRound=1,dealer=s.dealer;
  while(s.status==='playing'){
   const cards=[...s.deck,...s.pile,...s.hands.flat(),...s.won.flat()];assert.equal(cards.length,52);assert.equal(new Set(cards).size,52);
   const seat=s.turn;s=play(s,seat,botCard(s.hands[seat],s.pile.at(-1),s.pile.length),random());
   if(s.round!==previousRound){assert.equal(s.dealer,1-dealer);previousRound=s.round;dealer=s.dealer;}
   assert.ok(++moves<5000);
  }
  assert.ok(Math.max(...s.total)>=101);assert.notEqual(s.total[0],s.total[1]);assert.equal(s.reason,'normal');
 }
});
test('bot decision API has only own hand and public board; keeps jack on empty board',()=>{
 assert.equal(botCard([10,5],null,0),5);assert.equal(botCard([10,5],3,4),10);assert.equal(botCard([10,5],18,1),5);
});
test('forfeits have separate result reasons and do not invent score',()=>{
 for(const reason of ['leave','timeout','disconnect']){const s=fixture();const f=forfeit(s,0,reason);assert.equal(f.winner,1);assert.equal(f.reason,reason);assert.deepEqual(f.total,s.total);}
});
test('equal totals at or beyond target continue into another round',()=>{
 const s=fixture({pile:[4],hand:[1],played:47,deck:[],opponent:[]});
 s.target=101;s.won=[[0],[13]];
 const after=structuredClone(s);after.won[1].push(4,1);
 const scores=roundScore(after);s.total=scores.map(n=>101-n);
 const next=play(s,0,1,random());
 assert.deepEqual(next.total,[101,101]);assert.equal(next.status,'playing');assert.equal(next.round,2);
});
