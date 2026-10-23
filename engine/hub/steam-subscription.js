(() => {
 const expected=__ARIA_ID__,trigger=__ARIA_TRIGGER__,client=__ARIA_CLIENT__;
 const reply=status=>({status,id:expected,clientMatches:client&&typeof g_steamID!=='undefined'&&g_steamID?String(g_steamID)===client:null});
 let url;try{url=new URL(location.href)}catch{return{status:'wrong-page'}}
 if(url.protocol!=='https:'||url.hostname!=='steamcommunity.com'||url.pathname!=='/sharedfiles/filedetails/'||url.searchParams.get('id')!==expected)return{status:'wrong-page'};
 const app=document.querySelector('#sharedfiles_content_ctn')?.getAttribute('data-miniprofile-appid');
 if(app!=='431960')return reply('wrong-app');
 const add=document.getElementById('SubscribeItemOptionAdd'),sub=document.getElementById('SubscribeItemOptionSubscribed'),button=document.getElementById('SubscribeItemBtn');
 if(!add||!sub||!button)return reply('unsupported');
 const subscribed=sub.classList.contains('selected'),unsubscribed=add.classList.contains('selected');
 if(subscribed&&!unsubscribed)return reply('subscribed');
 if(!unsubscribed||subscribed)return reply('unsupported');
 if(typeof g_steamID==='undefined'||!g_steamID)return reply('login-required');
 if(trigger){try{button.click();return reply('submitted')}catch{return reply('error')}}
 return reply('unsubscribed');
})()