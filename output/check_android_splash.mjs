import {execFileSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
const adb='C:/Users/nihat/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const run=(args)=>execFileSync(adb,['-s','emulator-5554',...args],{maxBuffer:20*1024*1024});
run(['shell','am','force-stop','com.okeyix.game']);
run(['shell','am','start','-n','com.okeyix.game/.MainActivity']);
const start=Date.now();
for(const ms of [0,300,800,1600,3000,6000,10000]) {
 const delay=ms-(Date.now()-start);
 if(delay>0)await new Promise(ok=>setTimeout(ok,delay));
 writeFileSync(`output/android_splash_after_${ms}.png`,run(['exec-out','screencap','-p']));
 console.log(`Captured launch +${Date.now()-start}ms`);
}
