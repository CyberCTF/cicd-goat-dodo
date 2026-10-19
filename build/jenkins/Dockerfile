# Wonderland's Jenkins controller. Configured entirely by Configuration-as-Code (casc/jenkins.yaml)
# with a Job DSL seed that creates the dodo deploy pipeline. The pipeline is FIXED here (not read
# from the repository), which is what makes this a flow-control / gate-bypass challenge rather than
# pipeline poisoning: the attacker controls only the repository's contents, not the pipeline. The
# flag is NOT here: the `flag` credential resolves at boot from a file the entrypoint stages out of
# the per-player input Isoloom mounts at run time. Runs as root so the entrypoint can read that
# root-only mounted secret; builds execute on the controller's own executor (`agent any`).
FROM jenkins/jenkins:lts-jdk21

USER root

# git + curl for the in-controller solver and SCM polling; python venv for Checkov, the IaC security
# scanner the pipeline runs as a deploy gate. Checkov is pinned and installed into its own venv
# (Debian's system Python is externally managed), then exposed on PATH as `checkov`.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/checkov \
 && /opt/checkov/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/checkov/bin/pip install --no-cache-dir checkov==3.3.29 \
 && ln -s /opt/checkov/bin/checkov /usr/local/bin/checkov \
 && /usr/local/bin/checkov --version

# Plugins (resolved for this controller version).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration-as-Code + the Job DSL seed, outside JENKINS_HOME so they are read as-is at boot.
COPY casc/ /usr/share/jenkins/casc/

COPY entrypoint.sh /usr/local/bin/dodo-jenkins-entrypoint.sh
COPY deploy.sh /usr/local/bin/dodo-deploy
COPY solve.sh /usr/local/bin/dodo-solve
RUN chmod 0755 /usr/local/bin/dodo-jenkins-entrypoint.sh /usr/local/bin/dodo-deploy /usr/local/bin/dodo-solve

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml \
    SECRETS=/run/lab/casc_secrets \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1024m"

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/dodo-jenkins-entrypoint.sh"]
