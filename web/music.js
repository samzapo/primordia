// Browser audio uses the authored sample bank and score. Web Audio mixes on
// its audio thread, independent of server snapshots and Godot's frame loop.
(() => {
  if (window.primordiaMusic) return;
  let RATE = 22050, base = [];
  let context, master, analyser, origin = 0, bank = [], lanes = [], sources = new Map();
  let volume = 0, error = '', loaded = false, scheduled = 0, generation = 0, dropped = 0;
  function graph() {
    if (context) return;
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) throw new Error('Web Audio is unavailable');
    context = new Audio({latencyHint:'interactive'});
    master = context.createGain(); master.gain.value = 0;
    analyser = context.createAnalyser(); analyser.fftSize = 256;
    master.connect(analyser); analyser.connect(context.destination);
    for(let i=0;i<7;i++)lanes.push(makeLane());
    origin=context.currentTime;
  }
  function makeLane(){
      const gain=context.createGain(), filter=context.createBiquadFilter(), pan=context.createStereoPanner(), acid=context.createWaveShaper();
      gain.gain.value=0;filter.type='lowpass';filter.frequency.value=5000;
      gain.connect(filter);filter.connect(acid);acid.connect(pan);pan.connect(master);
      // The authored tempo delay continues on the browser's audio clock.
      const delay=context.createDelay(2), feedback=context.createGain(), send=context.createGain();
      delay.delayTime.value=60/128*.75;feedback.gain.value=.26;send.gain.value=.18;
      pan.connect(send);send.connect(delay);delay.connect(master);delay.connect(feedback);feedback.connect(delay);
      return {gain,filter,pan,acid,delay,feedback,send,lastAcid:-1,id:null};
  }
  async function unlock() {
    try {graph();if(context.state!=='running'&&context.state!=='closed') await context.resume();}
    catch(e){error=String(e);}
  }
  for (const event of ['pointerdown','pointerup','touchend','click','keydown'])
    window.addEventListener(event,unlock,{capture:true,passive:true});
  async function init(manifest, initialVolume) {
    volume=initialVolume;
    try {
      base=manifest.base_notes;RATE=manifest.rate;
      if(!Array.isArray(base)||base.length!==17||!base.every(note=>Number.isInteger(note)&&note>=0&&note<=127)||!Number.isInteger(RATE)||RATE<8000||RATE>96000)throw new Error('Invalid music manifest');
      graph();const response=await fetch(manifest.file,{credentials:'same-origin'});
      if(!response.ok) throw new Error('Music bank HTTP '+response.status);
      const bytes=await response.arrayBuffer(), data=new DataView(bytes);
      const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),value=>value.toString(16).padStart(2,'0')).join('');
      if(digest!==manifest.sha256||bytes.byteLength!==manifest.bytes)throw new Error('Music bank checksum failed');
      if(data.byteLength<80||data.getUint32(0,true)!==0x50534d50||data.getUint32(4,true)!==1||data.getUint32(8,true)!==RATE||data.getUint32(12,true)!==17)throw new Error('Invalid music bank');
      let at=84;
      for(let i=0;i<17;i++){
        const count=data.getUint32(16+i*4,true);
        if(count<2||count>RATE*3||at+count*4>bytes.byteLength)throw new Error('Invalid music sample length');
        const buffer=context.createBuffer(1,count,RATE), samples=buffer.getChannelData(0);
        for(let j=0;j<count;j++)samples[j]=data.getFloat32(at+j*4,true);
        bank.push(buffer);at+=count*4;
      }
      if(at!==bytes.byteLength)throw new Error('Unexpected music bank trailing bytes');
      loaded=true;
    }catch(e){error=String(e);}
  }
  function reset(){
    generation++;
    for(const source of sources.keys()){try{source.stop();}catch(_){}}
    sources.clear();scheduled=0;dropped=0;
    if(context){
      master.gain.setValueAtTime(0,context.currentTime);
      for(const lane of lanes)for(const key of ['gain','filter','pan','acid','delay','feedback','send'])lane[key].disconnect();
      lanes=[];for(let i=0;i<7;i++)lanes.push(makeLane());origin=context.currentTime;
    }
  }
  function schedule(start, events, channels, gain) {
    if(!loaded||!context||context.state!=='running')return;
    volume=Math.max(0,Math.min(1,gain));const now=context.currentTime;
    master.gain.setTargetAtTime(volume*.88,now,.01);
    for(let i=0;i<7;i++){
      const source=channels[i]||{},lane=lanes[i];
      if(lane.id!==source.id){
        for(const [voice,record] of sources)if(record.lane===i){record.gainNode.gain.setTargetAtTime(0,now,.01);try{voice.stop(now+.035);}catch(_){}}
        lane.id=source.id;
      }
      lane.gain.gain.setTargetAtTime(Math.max(0,source.gain||0),now,.015);
      lane.pan.pan.setTargetAtTime(Math.max(-1,Math.min(1,source.pan||0)),now,.015);
      lane.filter.frequency.setTargetAtTime(400+6100*Math.pow(Math.max(0,Math.min(1,source.light??.75)),1.4),now,.02);
      const chemistry=Math.round(Math.max(0,Math.min(1,source.acid||0))*50)/50;
      if(chemistry!==lane.lastAcid){
        const curve=new Float32Array(1024);
        for(let j=0;j<curve.length;j++){const value=j/(curve.length-1)*2-1;curve[j]=chemistry>0?Math.tanh(value*(1+chemistry*2.5))/(1+chemistry*1.7):value;}
        lane.acid.curve=curve;lane.lastAcid=chemistry;
      }
    }
    for(const event of events){
      if(!Number.isInteger(event.instrument)||event.instrument<0||event.instrument>=bank.length||event.lane<0||event.lane>=7)continue;
      const when=origin+(start+event.offset)/RATE;if(when<now-.025)continue;
      let overlapping=0;
      for(const record of sources.values())if(record.start<=when&&record.end>when)overlapping++;
      if(overlapping>=40||sources.size>=160){dropped++;continue;}
      const source=context.createBufferSource(), gainNode=context.createGain();
      source.buffer=bank[event.instrument];source.playbackRate.value=Math.pow(2,(event.note-base[event.instrument])/12);
      gainNode.gain.value=Math.max(0,event.gain)*.9;source.connect(gainNode);gainNode.connect(lanes[event.lane].gain);
      sources.set(source,{start:when,end:when+source.buffer.duration/source.playbackRate.value,lane:event.lane,gainNode});source.onended=()=>{sources.delete(source);source.disconnect();gainNode.disconnect();};
      source.start(Math.max(now,when));scheduled++;
    }
  }
  function setVolume(gain){const wasAudible=volume>0;volume=Math.max(0,Math.min(1,gain));if(wasAudible&&volume===0)reset();if(master)master.gain.setTargetAtTime(volume*.88,context.currentTime,.01);}
  function status(){
    let rms=0,peak=0;
    if(analyser){const samples=new Float32Array(256);analyser.getFloatTimeDomainData(samples);for(const value of samples){rms+=value*value;peak=Math.max(peak,Math.abs(value));}rms=Math.sqrt(rms/samples.length);}
    return {ready:loaded,state:context?.state||'unavailable',frame:context?Math.max(0,Math.floor((context.currentTime-origin)*RATE)):0,volume,rms,peak,scheduled,voices:sources.size,generation,dropped,error};
  }
  window.primordiaMusic={init,unlock,reset,schedule,setVolume,status};
})();
