# Build
yarn
yarn run build:production
# activate theme and build blade templates
cd ../../..
phpenv local 7.2
php -d memory_limit=512M ~/wp-cli.phar --allow-root theme activate $FOLDER_NAME
php -d memory_limit=512M ~/wp-cli.phar --allow-root blade compile

# for some reason this command fails the first time, runs ok the second
php -d memory_limit=512M ~/wp-cli.phar --allow-root blade compile

# Deploy
git add --all :/
git commit -m "DEPLOYMENT"
git push servers HEAD:master --force
# If this is the first time you're running the deployment, you might try this next line instead in case you get a missing branch error:
# git push servers HEAD:refs/heads/master --force