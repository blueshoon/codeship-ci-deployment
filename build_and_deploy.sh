#!/bin/bash
# If any commands fail (exit code other than 0) entire script exits
set -e

# Check for required environment variables and make sure they are setup
: ${PROJECT_TYPE?"PROJECT_TYPE Missing"} # theme|plugin
: ${WPE_INSTALL?"WPE_INSTALL Missing"}   # subdomain for wpengine install 
: ${REPO_NAME?"REPO_NAME Missing"}       # repo name (Typically the folder name of the project)

# Set repo based on current branch, by default master=production, develop=staging
# @todo support custom branches

target_wpe_install=${WPE_INSTALL}

if [ "$CI_BRANCH" == "master" ]
then
    repo=production
else
    # repo=staging
    repo=production
fi

if [[ "$CI_BRANCH" == "qa" && -n "$WPE_QA_INSTALL" ]]
then
    target_wpe_install=${WPE_QA_INSTALL}
    repo=production
fi

# Build
yarn
yarn build:production
# activate theme and build blade templates
cd ../../..
phpenv local 7.2
php -d memory_limit=512M ~/wp-cli.phar --allow-root theme activate $FOLDER_NAME/resources
php -d memory_limit=512M ~/wp-cli.phar --allow-root blade compile

# for some reason this command fails the first time, runs ok the second
php -d memory_limit=512M ~/wp-cli.phar --allow-root blade compile

# Deploy
echo "Add remote"

git remote add ${repo} git@git.wpengine.com:${repo}/${target_wpe_install}.git

git config --global user.email CI_COMMITTER_EMAIL
git config --global user.name CI_COMMITTER_NAME
git config core.ignorecase false
git add --all
git commit -am "Deployment to ${target_wpe_install} $repo by $CI_COMMITTER_NAME from $CI_NAME"

git push ${force} ${repo} master