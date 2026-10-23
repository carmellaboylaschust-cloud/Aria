import {loadTheme} from './injector.mjs';
try{const theme=await loadTheme(process.argv[2]);console.log(JSON.stringify({id:theme.theme.id,valid:true}));}catch(error){console.error(error.message);process.exitCode=2;}
