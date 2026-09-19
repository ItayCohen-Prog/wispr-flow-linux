const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const {EventEmitter} = require('node:events');
const {spawnSync} = require('node:child_process');

test('a failed socket schedules one retry even when error and close both fire', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wispr-reconnect-'));
  try {
    const file = path.join(dir, 'index.js');
    fs.writeFileSync(file, 'const q=()=>{const n=new i.BrowserWindow({preload:require("path").resolve(__dirname,"status","preload.js"),title:"Flow Status Indicator"});return n};q();');
    assert.equal(spawnSync('bash', [path.resolve(__dirname,'../scripts/patches/linux-native-flowbar.sh'), file]).status, 0);
    const sockets = [], timers = [];
    function BrowserWindow() { this.webContents = {send(){}}; }
    const ctx = {__dirname:dir, process:{env:{WISPR_NATIVE_FLOWBAR:'1'}}, i:{BrowserWindow,ipcMain:new EventEmitter()}, require:name => name === 'path' ? path : {createConnection(){const s = new EventEmitter();s.destroy=()=>s.emit('close');s.write=()=>{};sockets.push(s);return s;}}, setTimeout:fn=>{timers.push(fn);return {unref(){}};}};
    vm.runInNewContext(fs.readFileSync(file,'utf8'),ctx);
    sockets[0].emit('error',new Error('test')); sockets[0].emit('close');
    assert.equal(timers.length,1);
    timers.shift()(); assert.equal(sockets.length,2);
    sockets[1].emit('error',new Error('test')); sockets[1].emit('close');
    assert.equal(timers.length,1);
  } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
