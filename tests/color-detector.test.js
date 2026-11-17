// Lightweight, dependency-free tests for the isolated page-color JS.
// Runs on any machine with Node; real WebKit visual testing still required.
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const path = require('path');
const source = fs.readFileSync(path.join(__dirname, '../AdaptiveChrome.swift'), 'utf8');
const found = source.match(/static let script = #"""([\s\S]*?)"""#/);
assert(found, 'Swift-embedded script not found');
const script = found[1];

function cssColor(text) {
  if (!text || text === 'transparent') return [0,0,0,0];
  if (text[0] === '#') {
    const h = text.slice(1);
    if (h.length === 6) return [0,2,4].map(i => parseInt(h.slice(i,i+2),16)).concat(255);
  }
  const m = /^rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/.exec(text);
  if (m) return [+m[1], +m[2], +m[3], Math.round(255*(m[4] === undefined ? 1 : +m[4]))];
  return [0,0,0,0];
}
class Element {
  constructor(backgroundColor='transparent', opts={}) {
    this.backgroundColor=backgroundColor; this.parentElement=opts.parent || null;
    this.isAccent=!!opts.accent; this.isOverlay=!!opts.overlay;
    this.backgroundImage=opts.backgroundImage || 'none';
  }
  closest() {return null;}
  getBoundingClientRect(){ return {width:this.isAccent?60:1000,height:800}; }
}
async function evaluate(options) {
  const reports=[];
  const root=new Element(options.root || 'transparent');
  const body=new Element(options.body || 'transparent',{parent:root,backgroundImage:options.gradient?'linear-gradient(red,blue)':'none'});
  const accent=new Element('#00cfcc',{parent:body,accent:true});
  const overlay=new Element(options.overlayColor || 'rgba(0, 0, 0, 0.42)',{parent:body,overlay:true});
  const document={
    documentElement:root, body,
    createElement(tag) {
      if (tag !== 'canvas') return new Element();
      return {getContext:()=>{
        let color='transparent';
        return {
          clearRect(){}, fillRect(){},
          set fillStyle(v){color=v;},
          get fillStyle(){return color;},
          getImageData(){return {data: cssColor(color)};}
        }
      }};
    },
    elementsFromPoint(x,y) {
      if (options.modal) return [overlay,body,root];
      if (options.accent && x > 450 && x < 550 && y < 12) return [accent,body,root];
      return [body,root];
    },
    querySelectorAll() {return [];},
    addEventListener(){},
  };
  const ctx={
    document, Element, innerWidth:1000, innerHeight:800,
    CSS:{supports:()=>true},
    getComputedStyle(el){return {
      backgroundColor:el.backgroundColor, backgroundImage:el.backgroundImage,
      position:el.isOverlay?'fixed':'static', opacity:'1',
      display:'block', visibility:'visible'
    }},
    MutationObserver: class {observe(){}},
    setTimeout, clearTimeout,
    addEventListener(){},
    webkit:{messageHandlers:{searchAdaptiveChrome:{postMessage(obj){reports.push(obj);}}}}
  };
  ctx.globalThis=ctx;
  vm.runInNewContext(script,ctx);
  await new Promise(resolve=>setTimeout(resolve,205));
  assert(reports.length>0, 'No report received');
  return JSON.parse(JSON.stringify(reports.at(-1)));
}
(async()=>{
  const dark=await evaluate({body:'#0c1418',accent:true});
  assert.strictEqual(dark.color,'#0c1418',`Bright accent leaked into chrome: ${JSON.stringify(dark)}`);
  assert.strictEqual(dark.dim,0);
  const modal=await evaluate({body:'#ffffff',modal:true});
  assert.strictEqual(modal.color,'#ffffff',`Overlay affected base: ${JSON.stringify(modal)}`);
  assert(Math.abs(modal.dim-0.42)<0.02,`Overlay not detected: ${JSON.stringify(modal)}`);
  assert.strictEqual(modal.shade,'#000000');
  const tinted=await evaluate({body:'#fdfdfd',modal:true,overlayColor:'rgba(30, 45, 60, 0.4)'});
  assert.strictEqual(tinted.shade,'#1e2d3c',`Colored overlay shade lost: ${JSON.stringify(tinted)}`);
  assert(Math.abs(tinted.dim-0.4)<0.02,`Tinted overlay alpha lost: ${JSON.stringify(tinted)}`);
  const light=await evaluate({body:'#0c1418',modal:true,overlayColor:'rgba(245, 250, 255, 0.32)'});
  assert.strictEqual(light.shade,'#f5faff',`Light overlay shade lost: ${JSON.stringify(light)}`);
  assert(Math.abs(light.dim-0.32)<0.02,`Light overlay alpha lost: ${JSON.stringify(light)}`);
  const gradient=await evaluate({gradient:true});
  assert(gradient.snapshot,`Expected bounded pixel fallback: ${JSON.stringify(gradient)}`);
  console.log('PASS: dark + accent:',dark);
  console.log('PASS: modal scrim:',modal);
  console.log('PASS: colored and light overlays:',tinted,light);
  console.log('PASS: gradient snapshot fallback:',gradient);
})().catch(error=>{console.error(error);process.exitCode=1;});