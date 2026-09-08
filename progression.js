/* Config contracts: PlayerTitleFramework and LevelUpAnnouncements v1.0.0.
   Both editors reuse the existing app navigation, ID database and button classes. */
(() => {
  'use strict';
  const {escapeHtml:e, name, copy, download, data} = window.GeneratorCore;
  const specs = {
    titles: {
      owner:'PlayerTitleFramework', noun:'Title',
      defaults:{announce_new_titles:true, online_broadcast_cooldown_seconds:'15', untitled_label:'No Title'},
      labels:{announce_new_titles:'Announce newly earned titles', online_broadcast_cooldown_seconds:'Online title broadcast cooldown (seconds)', untitled_label:'Untitled player label'},
      numbers:{online_broadcast_cooldown_seconds:[0,3600]},
      permissions:'[nodes]\nplayertitleframework.list = allow\nplayertitleframework.online = allow\nplayertitleframework.select = allow\nplayertitleframework.grant = deny\nplayertitleframework.revoke = deny\n',
      hint:'Title announcement tokens: [Player Name], [Title], [Title ID]. Title rewards support items and owned Pals. They are queued when a title is first granted.',
    },
    levels: {
      owner:'LevelUpAnnouncements', noun:'Milestone',
      defaults:{announce:true,poll_minutes:'1',default_message:'[Player Name] has reached level [level]!',announce_crossed_milestones:false,rewards_enabled:true,reward_notice:true,reward_notice_message:'Level rewards are waiting. Use !claimrewards to collect them.'},
      labels:{announce:'Announce level ups',poll_minutes:'Poll interval (minutes)',default_message:'Default announcement',announce_crossed_milestones:'Announce crossed message milestones',rewards_enabled:'Enable milestone rewards',reward_notice:'Notify players of queued rewards',reward_notice_message:'Reward notification'},
      numbers:{poll_minutes:[1,60]},
      permissions:'[nodes]\nlevelupannouncements.announce = allow\n',
      hint:'Announcement tokens: [Player Name], [Raw Player Name], [Player Title], [level], [old level], [new level]. Reward notification tokens: [levels], [level count]. Crossed rewards are queued independently of crossed announcement settings.',
    },
  };
  for (const [page,spec] of Object.entries(specs)) buildEditor(page,spec);
  function buildEditor(page,spec) {
    const titles=page==='titles';
    const $=suffix=>document.getElementById(`${page}-${suffix}`);
    let serial=0;
    let state={settings:{...spec.defaults},entries:[],selected:null,filter:'',extra:[],permissions:spec.permissions};
    const fresh=()=>({uid:++serial,id:titles?`title_${serial}`:String(Math.min(1000,serial*5)),name:'New title',announcement:'[Player Name] has earned the title [Title]!',message:'',override:false,rewards:[],extra:[]});
    const selected=()=>state.entries.find(x=>x.uid===state.selected);
    const button=(label,action)=>`<button type="button" class="button button-secondary button-small" data-action="${action}">${label}</button>`;
    function field(label,key,value,type='text',attr='') {
      return `<label>${e(label)}<input data-key="${key}" type="${type}" value="${e(value)}" ${attr}></label>`;
    }
    function flag(label,key,value) {
      return `<label>${e(label)}<select data-key="${key}"><option value="true"${value?' selected':''}>Yes</option><option value="false"${!value?' selected':''}>No</option></select></label>`;
    }
    const notify=text=>{$('validation').textContent=text;};
    function dirty() {$('output').value='';$('download').disabled=true;notify('Changed. Generate to validate the current configuration.');}
    function renderList() {
      const query=state.filter.trim().toLowerCase();
      $('list').innerHTML=state.entries.filter(x=>[x.id,x.name,x.message].join(' ').toLowerCase().includes(query)).map(x=>`<button type="button" class="button button-secondary shop-offer" data-entry="${x.uid}" aria-current="${x.uid===state.selected}">${e(titles?(x.name||x.id):'Level '+x.id)}<small>${e(titles?x.id:x.override?x.message:'Default announcement')} · ${x.rewards.length} reward rows</small></button>`).join('')||'<p class="shop-note">No matching entries.</p>';
    }
    function render() {
      renderList();const x=selected();$('title').textContent=x?(titles?x.name||x.id:'Level '+x.id):spec.owner+' settings';
      if(!x) {
        $('form').innerHTML=`<div class="shop-fields">${Object.entries(state.settings).map(([k,v])=>typeof spec.defaults[k]==='boolean'?flag(spec.labels[k],k,v):field(spec.labels[k],k,v,spec.numbers[k]?'number':'text',spec.numbers[k]?`min="${spec.numbers[k][0]}" max="${spec.numbers[k][1]}" step="1"`:'')).join('')}<label class="full-width">Permission sections (preserved on import)<textarea data-permissions rows="8">${e(state.permissions)}</textarea></label></div><p class="shop-note">${e(spec.hint)}</p>`;
        return;
      }
      $('form').innerHTML=`<div class="shop-controls">${button('Duplicate '+spec.noun,'duplicate')}${button('Remove '+spec.noun,'remove')}</div><div class="shop-fields">${field(titles?'Title ID':'Player level','id',x.id,titles?'text':'number',titles?'maxlength="96"':'min="1" max="1000" step="1"')}${titles?field('Display name','name',x.name)+field('Announcement','announcement',x.announcement):flag('Override announcement at this level','override',x.override)+(x.override?field('Milestone announcement','message',x.message):'')}</div><p class="shop-note">${e(spec.hint)}</p><section><h3>Rewards</h3>${x.rewards.map((r,i)=>`<div class="shop-line" data-index="${i}"><label>Reward kind<select data-row="kind">${(titles?['item','pal']:['item','pal','currency']).map(k=>`<option value="${k}"${r.kind===k?' selected':''}>${k==='currency'?'Credits':k==='pal'?'Owned Pal':'Item'}</option>`).join('')}</select></label>${r.kind==='currency'?'':`<label>${r.kind==='pal'?'Pal':'Item'} ID<input data-row="id" list="${r.kind==='pal'?'pal-options':'item-options'}" value="${e(r.id)}"></label>`}<label>Quantity<input data-row="amount" type="number" min="1" max="1000000000" step="1" value="${e(r.amount)}"></label>${r.kind==='pal'?`<label>Pal level<input data-row="level" type="number" min="1" max="100" step="1" value="${e(r.level)}"></label>`:''}<p class="reward-name">${e(r.kind==='currency'?'Credits — requires ServerShopFramework':name(r.kind==='pal'?'pals':'items',r.id))}</p><div class="shop-controls">${button('Duplicate Reward','duplicate-reward')}${button('Remove Reward','remove-reward')}</div></div>`).join('')}<div class="shop-controls">${button('Add Reward','add-reward')}</div><p class="shop-note">Gold Coins: Money. Dog Coins: DogCoin. Reward delivery uses PixelsPalmodCore. Unknown custom IDs generate a warning for server verification.</p></section>`;
    }
    function validate() {
      const errors=[],warnings=[],seen=new Set();
      const int=(v,min,max,path)=>{if(String(v).trim()===''||!Number.isSafeInteger(Number(v))||Number(v)<min||Number(v)>max)errors.push(`${path}: enter a whole number from ${min} to ${max}.`);};
      function text(v,max,path,required=false) {
        if(/[\r\n\x00]/.test(String(v))||String(v).length>max)errors.push(`${path}: use a single line of at most ${max} characters.`);
        if(required&&!String(v).trim())errors.push(`${path}: a value is required.`);
        // Palladium coerces bare boolean/number values; these are not safe text IDs.
      }
      for(const [k,v] of Object.entries(state.settings)) {
        if(spec.numbers[k])int(v,...spec.numbers[k],spec.labels[k]);
        else if(typeof v!=='boolean')text(v,k==='untitled_label'?64:512,spec.labels[k],true);
      }
      for(const x of state.entries) {
        const key=titles?x.id.toLowerCase():String(Number(x.id));
        if(seen.has(key))errors.push(`Duplicate ${titles?'title ID':'level'}: ${x.id}`);seen.add(key);
        if(titles) {
          if(!/^[A-Za-z_][A-Za-z0-9_]{0,95}$/.test(x.id))errors.push(`${x.id||'Title'}: ID must start with a letter or underscore and contain only letters, digits or underscores (maximum 96).`);
          text(x.name,64,x.id+' display name',true);text(x.announcement,512,x.id+' announcement');
        } else {
          int(x.id,1,1000,'Milestone level');
          if(x.override)text(x.message,512,'Level '+x.id+' message',true);
          if(!x.override&&!x.rewards.length&&!x.extra.length)errors.push(`Level ${x.id}: add a message override or a reward, or remove this empty milestone.`);
        }
        if(x.rewards.length>128)errors.push(`${x.id}: maximum 128 combined reward rows.`);
        x.rewards.forEach((r,i)=>{
          const path=`${x.id} reward ${i+1}`;
          if(!(titles?['item','pal']:['item','pal','currency']).includes(r.kind))errors.push(`${path}: unsupported reward kind ${r.kind}.`);
          int(r.amount,1,1000000000,path+' quantity');
          if(r.kind==='pal')int(r.level,1,100,path+' Pal level');
          if(r.kind!=='currency') {
            text(r.id,128,path+' ID',true);
            if(/^(true|false)$/i.test(r.id)||(!isNaN(Number(r.id))&&r.id.trim()))errors.push(`${path}: the ID must be text, not a boolean or number.`);
            if(!(data[r.kind==='pal'?'pals':'items']||[]).some(row=>row.id===r.id))warnings.push(`${path}: ${r.id} is absent from the shared ID database; verify the custom ID on the server.`);
          } else if(r.id)errors.push(`${path}: currency rewards must not include an ID.`);
        });
      }
      let section=false;const permissionKeys=new Set();let sectionName='';
      state.permissions.split(/\r?\n/).forEach((raw,i)=>{
        const line=raw.trim();if(!line||/^[;#]/.test(line))return;
        const header=/^\[([^\]\r\n]+)\]$/.exec(line);
        if(header){section=true;sectionName=header[1];return;}
        const m=/^([\w.]+)\s*=\s*(allow|deny)$/.exec(line);
        if(!section||!m)errors.push(`Permissions line ${i+1}: use a section header followed by node = allow or node = deny.`);
        else {const key=sectionName+'.'+m[1];if(permissionKeys.has(key))errors.push(`Duplicate permission: ${key}`);permissionKeys.add(key);}
      });
      if(state.extra.length||state.entries.some(x=>x.extra.length||x.rewards.some(r=>r.extra?.length)))warnings.push('Additional imported keys are retained. Their behavior is outside this editor’s validated schema; review the generated text.');
      return {errors,warnings};
    }
    function generate() {
      const {errors,warnings}=validate();
      if(errors.length){dirty();notify('Not generated:\n'+errors.join('\n'));return null;}
      const lines=[`; ${spec.owner} v1.0.0 settings — Palworld Config Generator`];
      const put=(k,v)=>lines.push(`${k} = ${String(v).trim()}`);
      Object.entries(state.settings).forEach(([k,v])=>put(k,v));state.extra.forEach(([k,v])=>put(k,v));
      for(const x of state.entries) {
        lines.push('');
        const id=titles?x.id:String(Number(x.id));
        if(titles){put(`titles.${id}.name`,x.name);if(x.announcement.trim())put(`titles.${id}.announcement`,x.announcement);}
        else if(x.override)put(`messages.${id}`,x.message);
        let item=0,pal=0;
        x.rewards.forEach((r,i)=>{
          const prefix=titles?`titles.${id}.${r.kind==='pal'?'pals.'+(++pal):'items.'+(++item)}.`:`level_rewards.${id}.${i+1}.`;
          if(!titles)put(prefix+'kind',r.kind);
          if(r.kind!=='currency')put(prefix+(titles?(r.kind==='pal'?'species':'item'):'id'),r.id);
          put(prefix+(titles?'count':'amount'),Number(r.amount));
          if(r.kind==='pal')put(prefix+'level',Number(r.level));
          (r.extra||[]).forEach(([k,v])=>put(prefix+k,v));
        });
        x.extra.forEach(([k,v])=>put((titles?`titles.${id}.`:`level_rewards.${id}.`)+k,v));
      }
      if(state.permissions.trim())lines.push('',state.permissions.trim());
      const result=lines.join('\n')+'\n';$('output').value=result;$('download').disabled=false;
      notify(`Valid: ${state.entries.length} ${titles?'titles':'milestones'}.`+(warnings.length?'\nWarnings:\n'+warnings.join('\n'):''));return result;
    }
    function importText(input) {
      const next={settings:{...spec.defaults},entries:[],selected:null,filter:'',extra:[],permissions:''};
      const entries=new Map(),keys=new Set();let sections=false;
      const get=id=>{if(!entries.has(id)){const x=fresh();x.id=id;x.rewards=[];x.extra=[];if(titles){x.name=id;x.announcement='[Player Name] has earned the title [Title]!';}entries.set(id,{x,rows:new Map()});}return entries.get(id);};
      String(input).replace(/^\uFEFF/,'').split(/\r?\n/).forEach((raw,i)=>{
        const line=raw.trim();if(sections||line.startsWith('[')){sections=true;next.permissions+=raw+'\n';return;}
        if(!line||/^[;#]/.test(line))return;
        const match=/^([\w.]+)\s*=\s*(.*)$/.exec(line);if(!match)throw Error(`Line ${i+1}: invalid config assignment.`);
        const [,k,v]=match;
        // Numeric key segments are numbers in Palladium (01 and 1 alias).
        const canonical=k.split('.').map(part=>/^\d+$/.test(part)?String(Number(part)):part).join('.');
        if(keys.has(canonical))throw Error(`Line ${i+1}: duplicate key ${k}.`);
        for(const prior of keys)if(canonical.startsWith(prior+'.')||prior.startsWith(canonical+'.'))throw Error(`Line ${i+1}: conflicting scalar and nested keys ${k}.`);
        keys.add(canonical);
        if(Object.hasOwn(next.settings,k)) {
          if(typeof spec.defaults[k]==='boolean'){if(!['true','false'].includes(v))throw Error(`${k}: true or false required.`);next.settings[k]=v==='true';}
          else next.settings[k]=v;
          return;
        }
        if(titles&&k.startsWith('titles.')) {
          const m=/^titles\.([\w]+)\.(.+)$/.exec(k);if(!m)throw Error(`Invalid title path ${k}.`);
          const {x,rows}=get(m[1]),tail=m[2];
          if(['name','announcement'].includes(tail)){x[tail]=v;return;}
          if(/^(items|pals)(\.|$)/.test(tail)) {
            const r=/^(items|pals)\.([1-9]\d*)\.([\w]+)$/.exec(tail);if(!r)throw Error(`Invalid numbered reward ${k}.`);
            const rowKey=r[1]+'.'+r[2];if(!rows.has(rowKey))rows.set(rowKey,{kind:r[1]==='pals'?'pal':'item',index:Number(r[2]),raw:{}});
            rows.get(rowKey).raw[r[3]]=v;return;
          }
          x.extra.push([tail,v]);return;
        }
        if(!titles&&k.startsWith('messages.')) {
          const m=/^messages\.([1-9]\d*)$/.exec(k);if(!m)throw Error(`Invalid message level ${k}.`);
          const {x}=get(m[1]);x.message=v;x.override=true;return;
        }
        if(!titles&&k.startsWith('level_rewards.')) {
          const m=/^level_rewards\.([1-9]\d*)\.([1-9]\d*)\.([\w]+)$/.exec(k);if(!m)throw Error(`Invalid level reward path ${k}.`);
          const {rows}=get(m[1]);if(!rows.has(m[2]))rows.set(m[2],{index:Number(m[2]),raw:{}});rows.get(m[2]).raw[m[3]]=v;return;
        }
        if(['titles','messages','level_rewards'].includes(k))throw Error(`${k}: use numbered/named child entries instead of a scalar.`);
        next.extra.push([k,v]);
      });
      for(const {x,rows} of entries.values()) {
        x.rewards=[...rows.values()].sort((a,b)=>(a.kind||'').localeCompare(b.kind||'')||a.index-b.index).map(row=>{
          const r=row.raw;const kind=titles?row.kind:String(r.kind||'').toLowerCase();
          if(kind==='currency'&&Object.hasOwn(r,'id'))throw Error(`Level ${x.id}: currency rewards cannot specify id.`);
          // Accept runtime aliases but refuse ambiguous aliases with different values.
          const aliases=(names,fallback)=>{const found=names.filter(k=>Object.hasOwn(r,k));if(found.some(k=>r[k]!==r[found[0]]))throw Error(`${x.id}: conflicting reward aliases ${found.join(', ')}.`);return found.length?r[found[0]]:fallback;};
          const known=['kind','item','species','id','reward','count','amount','level'];
          return {kind,id:aliases(titles?(kind==='pal'?['species','id']:['item','id']):['id','item','species','reward'],''),amount:aliases(titles?['count','amount']:['amount','count'],titles?'1':''),level:r.level??'1',extra:Object.entries(r).filter(([k])=>!known.includes(k))};
        });next.entries.push(x);
      }
      state=next;$('search').value='';dirty();render();
      const result=validate();notify(result.errors.length?'Loaded with errors:\n'+result.errors.join('\n'):'Loaded. Generate to validate and export.');
    }
    $('form').addEventListener('submit',event=>event.preventDefault());
    $('form').addEventListener('input',event=>{
      const t=event.target,x=selected();
      if(t.hasAttribute('data-permissions'))state.permissions=t.value;
      else if(t.dataset.row&&x){const row=x.rewards[Number(t.closest('[data-index]').dataset.index)];row[t.dataset.row]=t.value;if(t.dataset.row==='kind'){row.id='';row.extra=[];render();}}
      else if(t.dataset.key){const dest=x||state.settings,key=t.dataset.key;dest[key]=typeof dest[key]==='boolean'?t.value==='true':t.value;if(key==='override')render();}
      else return;
      dirty();renderList();
    });
    $('form').addEventListener('click',event=>{
      const b=event.target.closest('[data-action]');if(!b)return;const x=selected();if(!x)return;
      const index=Number(b.closest('[data-index]')?.dataset.index);
      switch(b.dataset.action) {
        case 'add-reward':x.rewards.push({kind:'item',id:'PalSphere',amount:'1',level:'1',extra:[]});break;
        case 'duplicate-reward':x.rewards.splice(index+1,0,structuredClone(x.rewards[index]));break;
        case 'remove-reward':x.rewards.splice(index,1);break;
        case 'remove':state.entries=state.entries.filter(v=>v!==x);state.selected=null;break;
        case 'duplicate':{
          const clone=structuredClone(x);clone.uid=++serial;
          if(titles){let n=1;do{clone.id=x.id+'_copy'+n++;}while(state.entries.some(v=>v.id.toLowerCase()===clone.id.toLowerCase()));}
          else {let n=1;while(state.entries.some(v=>Number(v.id)===n))n++;clone.id=String(n);}
          state.entries.splice(state.entries.indexOf(x)+1,0,clone);state.selected=clone.uid;break;
        }
        default:return;
      }
      dirty();render();
    });
    $('add').onclick=()=>{const x=fresh();if(titles){while(state.entries.some(v=>v.id.toLowerCase()===x.id.toLowerCase()))x.id='title_'+(++serial);}else {let n=1;while(state.entries.some(v=>Number(v.id)===n))n++;x.id=String(n);}state.entries.push(x);state.selected=x.uid;dirty();render();};
    $('settings').onclick=()=>{state.selected=null;render();};
    $('list').onclick=event=>{const b=event.target.closest('[data-entry]');if(b){state.selected=Number(b.dataset.entry);render();}};
    $('search').oninput=event=>{state.filter=event.target.value;renderList();};
    for(const id of ['generate','generate-top'])$(id).onclick=generate;
    for(const id of ['copy','copy-top'])$(id).onclick=async()=>{const text=generate();if(text!==null){try{notify(await copy(text)?'Config copied.':'Copy failed. Select the generated output and copy it manually.');}catch(_){notify('Copy failed. Select the generated output and copy it manually.');}}};
    $('download').onclick=()=>{const text=generate();if(text!==null)download('settings.config',text);};
    $('load').onclick=()=>$('file').click();
    $('file').onchange=async event=>{const file=event.target.files[0];if(!file)return;try{importText(await file.text());}catch(err){notify('Load failed; current edits were kept. '+err.message);}finally{event.target.value='';}};
    render();
  }
})();
