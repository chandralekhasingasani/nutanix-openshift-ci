import {handler} from './index.js'


let response = await handler(null,{logStreamName: "logstream"})
console.log(response)
