const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
const patch = path.resolve(__dirname, '../scripts/patches/linux-background-launch.sh');
const fixture = `
const b=()=>i.app.isPackaged?d.RA.prefs?.isUpdating?(a().info("Not showing hub window at launch: app is updating"),!1):i.app.getLoginItemSettings().wasOpenedAtLogin?!1:!0:!0;
e.app.on("second-instance",(t,r)=>{if(r.includes("--quit-app"))return e.app.quit();const x=r.find(e=>e.startsWith("--squirrel-"));if(x){}else{if(platform.H8){const e=P(r.find(e=>e.startsWith("wispr-flow:")));if(e)return void U(e)}n().info("User tried to open the app a second time while it was already running"),hub.show()}});
`;
function withPatch(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wispr-background-'));
  try {
    const file = path.join(dir,'index.js'); fs.writeFileSync(file, fixture);
    assert.equal(spawnSync('bash',[patch,file],{encoding:'utf8'}).status,0);
    fn(file,fs.readFileSync(file,'utf8'));
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
}
function run(code,{argv=[],platform='linux',onboarded=true}={}) {
  const calls=[]; let handler;
  const context = {process:{argv,platform},i:{app:{isPackaged:true,getLoginItemSettings:()=>({})}},d:{RA:{prefs:{user:{onboardingCompleted:onboarded}}}},a:()=>({info:()=>{}}),n:()=>({info:()=>{}}),e:{app:{on:(_,fn)=>handler=fn,quit:()=>calls.push('quit')}},platform:{H8:platform==='win32'},P:x=>x,U:x=>calls.push(x),hub:{show:()=>calls.push('show')}};
  vm.createContext(context); vm.runInContext(code,context);
  return {show:vm.runInContext('b()',context),second:args=>{handler({},args);return calls;}};
}
test('background startup preserves onboarding and explicit Hub requests',()=>withPatch((_,s)=>{
  assert.equal(run(s,{argv:['--background']}).show,false);
  assert.equal(run(s,{argv:['--background'],onboarded:false}).show,true);
  assert.equal(run(s,{argv:['--background','--show-hub']}).show,true);
  assert.equal(run(s).show,true);
  assert.equal(run(s,{argv:['--background'],platform:'darwin'}).show,true);
}));
test('second instance preserves quit, deep links and explicit Hub requests',()=>withPatch((_,s)=>{
  assert.deepEqual(run(s).second(['--background']),[]);
  assert.deepEqual(run(s).second(['--background','--show-hub']),['show']);
  assert.deepEqual(run(s).second(['--background','--quit-app']),['quit']);
  assert.deepEqual(run(s).second(['--background','wispr-flow://test']),['wispr-flow://test']);
}));
test('patch is idempotent and refuses unknown bundle shapes without edits',()=>withPatch((file,s)=>{
  assert.equal(spawnSync('bash',[patch,file]).status,0);
  assert.equal(fs.readFileSync(file,'utf8'),s);
  fs.writeFileSync(file,'const changed=true;');
  assert.notEqual(spawnSync('bash',[patch,file]).status,0);
  assert.equal(fs.readFileSync(file,'utf8'),'const changed=true;');
}));
