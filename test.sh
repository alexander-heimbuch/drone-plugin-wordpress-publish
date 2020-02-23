#!/bin/sh

docker run --rm \
    -v $(pwd):$(pwd) \
    -w $(pwd) \
    -e PLUGIN_PLUGINSLUG="test-plugin" \
    -e PLUGIN_PLUGINDIR="test-plugin" \
    -e PLUGIN_ASSETSDIR="assets" \
    -e PLUGIN_MAINFILE="test-plugin.php" \
    -e PLUGIN_WORDPRESS_USER="wordpress-user" \
    -e PLUGIN_WORDPRESS_PASSWORD="wordpress-password" \
    plugins/wordpress-publish