import { Octokit, App } from "octokit";
import request from 'request';
import fs from 'fs'
import { createAppAuth } from "@octokit/auth-app";

function timestamp(param){
    const dateObject = new Date();
    const date = dateObject.getDate();
    const month = dateObject.getMonth();
    const year = dateObject.getFullYear();
    const hours = dateObject.getHours();
    const minutes = dateObject.getMinutes();
    const seconds = dateObject.getSeconds();
    if(param==1)
    {
        return `${year}-${month}-${date} ${hours}:${minutes}:${seconds} [INFO]`
    }
    else
    {
        return `${year}-${month}-${date} ${hours}:${minutes}:${seconds} [WARNING]`
    }
}

async function main(privateKey,app_id,installation_id){
    const appId = app_id
    const installationId = installation_id

    const app = new App({
        appId: appId,
        privateKey: privateKey
    });

    const octokit = new Octokit({
        authStrategy: createAppAuth,
        auth: {
            appId: appId,
            installationId: installationId,
            privateKey: privateKey
        },
    });

        for await (const { octokit, repository } of app.eachRepository.iterator()) {
            const comparison = await octokit.rest.repos.compareCommits({
                 owner: repository.owner.login ,
                 repo: repository.name ,
                 head: 'main',
                 base: 'chandralek:main'
             })
            console.log(timestamp(1)," Is Upstream identical to forked  repository ",repository.name,"  ? " , comparison.data.status)
        try{
         if(comparison.data.status!='identical')
            {
                console.log(timestamp(0), " Upstream is not identical to forked repository ",repository.name)
                await octokit.rest.repos.mergeUpstream({
                repo: repository.name,
                owner: repository.owner.login,
                branch: 'main'
            });
                console.log(timestamp(1), " Called api to fetch and merge with upstream for repository ",repository.name)
            }
            }
        catch (e) {
            console.error(timestamp(0)," " ,e)
        }
    }
}

fs.readFile('file.pem', 'utf8', function(err, data) {
      if (err) throw err;
      main(data,process.argv[2],process.argv[3])
  });
