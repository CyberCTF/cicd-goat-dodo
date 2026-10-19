// Seed job (run by Configuration-as-Code) that creates Wonderland's dodo deploy pipeline.
//
// The pipeline is defined HERE, inline — NOT read from a Jenkinsfile in the repository. That is the
// crux of this challenge (CICD-SEC-1, Insufficient Flow Control): the attacker can change what the
// repository contains, but NOT what the pipeline does. The only control between a malicious change
// and a deploy is the security scan — and that scan reads its configuration from the repository, so
// it can be neutered from inside the repo. The job polls the dodo repo over git every minute (an
// SCM poll, no inbound webhook, no Gitea plugin), so a push to main runs the pipeline on its own.
pipelineJob('wonderland-dodo') {
    displayName('Wonderland » dodo (scan & deploy)')
    definition {
        cps {
            sandbox(true)
            script('''
pipeline {
    agent any
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
    }
    triggers {
        pollSCM('* * * * *')
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'http://gitea:3000/Wonderland/dodo.git', credentialsId: 'gitea-jenkins'
            }
        }
        stage('Security Scan (deploy gate)') {
            // The gate: Checkov refuses a publicly-readable bucket. It auto-loads a repository-local
            // .checkov.yaml, so a change can override its own scan. A non-zero exit fails the stage
            // and the deploy below never runs.
            steps {
                sh 'checkov -d . --check CKV_AWS_20 --compact'
            }
        }
        stage('Deploy') {
            // Past the gate: deploy, and publish the release token only if a public bucket was
            // actually deployed. $flag is the Global-scope credential, available only inside here.
            steps {
                withCredentials([string(credentialsId: 'flag', variable: 'flag')]) {
                    sh 'sh /usr/local/bin/dodo-deploy'
                }
            }
        }
    }
    post {
        always {
            cleanWs()
        }
    }
}
'''.stripIndent())
        }
    }
}
