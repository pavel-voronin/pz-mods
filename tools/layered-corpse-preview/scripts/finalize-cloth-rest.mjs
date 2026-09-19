import {finalizeClothRestFile} from './finalize-cloth-rest.ts';
for(const dir of process.argv.slice(2))console.log(dir,await finalizeClothRestFile(dir));
