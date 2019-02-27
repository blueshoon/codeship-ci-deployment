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
    repo=production
    # repo=staging
fi

if [[ "$CI_BRANCH" == "qa" && -n "$WPE_QA_INSTALL" ]]
then
    target_wpe_install=${WPE_QA_INSTALL}
    repo=production
fi

# Begin from the ~/clone directory
# this directory is the default your git project is checked out into by Codeship.
cd ~/clone

# Build
yarn
yarn build:production
cd

# download copy of wp core - wp install is needed only in order to cache templates
php -d memory_limit=768M ~/wp-cli.phar core download

# db, user, and pw are all env vars provided by codeship
php -d memory_limit=768M ~/wp-cli.phar config create --dbname=test --dbuser=root --dbpass=test
php -d memory_limit=768M ~/wp-cli.phar core install --url=example.com --title=Example --admin_user=supervisor --admin_password=strongpassword --admin_email=info@example.com

# install modules
mkdir -p wp-content/themes/$FOLDER_NAME
rsync -a ~/clone/* wp-content/themes/$FOLDER_NAME
cd wp-content/themes/$FOLDER_NAME

phpenv local 7.2
composer install --prefer-dist  --no-interaction

# activate theme and build blade templates
cd ../../..
phpenv local 7.2
php -d memory_limit=512M ~/wp-cli.phar --allow-root theme activate $FOLDER_NAME/resources
php -d memory_limit=512M ~/wp-cli.phar --allow-root blade compile

# for some reason this command fails the first time, runs ok the second
php -d memory_limit=512M ~/wp-cli.phar --allow-root blade compile

# Get official list of files/folders that are not meant to be on production if $EXCLUDE_LIST is not set.
if [[ -z "${EXCLUDE_LIST}" ]];
then
    wget https://raw.githubusercontent.com/blueshoon/codeship-ci-deployment/master/exclude-list.txt
else
    # @todo validate proper url?
    wget ${EXCLUDE_LIST}
fi

# Loop over list of files/folders and remove them from deployment
ITEMS=`cat exclude-list.txt`
for ITEM in $ITEMS; do
    if [[ $ITEM == *.* ]]
    then
        find . -depth -name "$ITEM" -type f -exec rm "{}" \;
    else
        find . -depth -name "$ITEM" -type d -exec rm -rf "{}" \;
    fi
done

# Remove exclude-list file
rm exclude-list.txt

# Clone the WPEngine files to the deployment directory
# if we are not force pushing our changes
if [[ $CI_MESSAGE != *#force* ]]
then
    force=''
    git clone git@git.wpengine.com:${repo}/${target_wpe_install}.git ~/deployment
else
    force='-f'
    if [ ! -d "~/deployment" ]; then
        mkdir ~/deployment
        cd ~/deployment
        git init
    fi
fi

# If there was a problem cloning, exit
if [ "$?" != "0" ] ; then
    echo "Unable to clone ${repo}"
    kill -SIGINT $$
fi

# Move the gitignore file to the deployments folder
cd ~/deployment
wget --output-document=.gitignore https://raw.githubusercontent.com/linchpin/wpengine-codeship-continuous-deployment/master/gitignore-template.txt

# Delete plugin/theme if it exists, and move cleaned version into deployment folder
rm -rf /wp-content/${PROJECT_TYPE}s/${REPO_NAME}

# Check to see if the wp-content directory exists, if not create it
if [ ! -d "./wp-content" ]; then
    mkdir ./wp-content
fi
# Check to see if the plugins directory exists, if not create it
if [ ! -d "./wp-content/plugins" ]; then
    mkdir ./wp-content/plugins
fi
# Check to see if the themes directory exists, if not create it
if [ ! -d "./wp-content/themes" ]; then
    mkdir ./wp-content/themes
fi

rsync -a ~/wp-content/themes/$FOLDER_NAME/* ./wp-content/${PROJECT_TYPE}s/${REPO_NAME}

# Stage, commit, and push to wpengine repo

echo "Add remote"

git remote add ${repo} git@git.wpengine.com:${repo}/${target_wpe_install}.git &> /dev/null

git config --global user.email CI_COMMITTER_EMAIL
git config --global user.name CI_COMMITTER_NAME
git config core.ignorecase false
git add --all
git commit -am "Deployment to ${target_wpe_install} $repo by $CI_COMMITTER_NAME from $CI_NAME"

git push ${force} ${repo} master -vvv