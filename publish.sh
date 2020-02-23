#! /bin/bash
# See https://github.com/GaryJones/wordpress-plugin-svn-deploy for instructions and credits.
#
# Steps to deploying:
#
#  1. Check local plugin directory exists.
#  2. Check local SVN assets directory exists.
#  3. Check main plugin file exists.
#  4. Check readme.txt version matches main plugin file version.
#  5. Checkout SVN repo.
#  6. Set to SVN ignore some GitHub-related files.
#  7. Export HEAD of master from git to the trunk of SVN.
#  8. Initialise and update and git submodules.
#  9. Move /trunk/assets up to /assets.
# 10. Move into /trunk, and SVN commit.
# 11. Move into /assets, and SVN commit.
# 12. Copy /trunk into /tags/{version}, and SVN commit.

echo
echo "WordPress Plugin SVN Deploy v4.1.0"
echo

# Set up some default values. Feel free to change these in your own script
SVNPATH="/tmp/svn"
SVNURL="https://plugins.svn.wordpress.org/$PLUGIN_PLUGINSLUG"

# Check directory exists.
if [ ! -d "$PLUGIN_PLUGINDIR" ]; then
	echo "Directory $PLUGIN_PLUGINDIR not found. Aborting."
	exit 1
fi

# Check if SVN assets directory exists.
if [ ! -d "$PLUGIN_PLUGINDIR/$PLUGIN_ASSETSDIR" ]; then
	echo "SVN assets directory $PLUGIN_PLUGINDIR/$PLUGIN_ASSETSDIR not found."
	echo "This is not fatal but you may not have intended results."
	echo
fi

# Check main plugin file exists.
if [ ! -f "$PLUGIN_PLUGINDIR/$PLUGIN_MAINFILE" ]; then
	echo "Plugin file $PLUGIN_PLUGINDIR/$PLUGIN_MAINFILE not found. Aborting."
	exit 1
fi

echo "Checking version in main plugin file matches version in readme.txt file..."
echo

# Check version in readme.txt is the same as plugin file after translating both to Unix line breaks to work around grep's failure to identify Mac line breaks
PLUGINVERSION=$(grep -i "Version:" $PLUGIN_PLUGINDIR/$PLUGIN_MAINFILE | awk -F' ' '{print $NF}' | tr -d '\r')
echo "$PLUGIN_MAINFILE version: $PLUGINVERSION"
READMEVERSION=$(grep -i "Stable tag:" $PLUGIN_PLUGINDIR/readme.txt | awk -F' ' '{print $NF}' | tr -d '\r')
echo "readme.txt version: $READMEVERSION"

if [ "$READMEVERSION" = "trunk" ]; then
	echo "Version in readme.txt & $PLUGIN_MAINFILE don't match, but Stable tag is trunk. Let's continue..."
elif [ "$PLUGINVERSION" != "$READMEVERSION" ]; then
	echo "Version in readme.txt & $PLUGIN_MAINFILE don't match. Exiting...."
	exit 1
elif [ "$PLUGINVERSION" = "$READMEVERSION" ]; then
	echo "Versions match in readme.txt and $PLUGIN_MAINFILE. Let's continue..."
fi

echo

echo "Slug: $PLUGIN_PLUGINSLUG"
echo "Plugin directory: $PLUGIN_PLUGINDIR"
echo "Main file: $PLUGIN_MAINFILE"
echo "Temp checkout path: $SVNPATH"
echo "Remote SVN repo: $SVNURL"
echo "SVN username: $PLUGIN_SVNUSER"
echo

# Let's begin...
echo ".........................................."
echo
echo "Preparing to deploy WordPress plugin"
echo
echo ".........................................."
echo

echo

echo "Changing to $PLUGIN_PLUGINDIR"
cd $PLUGIN_PLUGINDIR

echo "Creating local copy of SVN repo trunk..."
svn checkout $SVNURL $SVNPATH --depth immediates
svn update --quiet $SVNPATH/trunk --set-depth infinity
svn update --quiet $SVNPATH/tags/$PLUGINVERSION --set-depth infinity

echo "Ignoring GitHub specific files"
# Use local .svnignore if present
if [ -f ".svnignore" ]; then
	echo "Using local .svnignore"
	SVNIGNORE=$(<.svnignore)
else
	echo "Using default .svnignore"
	SVNIGNORE="README.md
Thumbs.db
.github
.git
.gitattributes
.gitignore
composer.lock"
fi

svn propset svn:ignore \""$SVNIGNORE"\" "$SVNPATH/trunk/"

echo "Exporting the HEAD of master from git to the trunk of SVN"
git checkout-index -a -f --prefix=$SVNPATH/trunk/

# If submodule exist, recursively check out their indexes
if [ -f ".gitmodules" ]; then
	echo "Exporting the HEAD of each submodule from git to the trunk of SVN"
	git submodule init
	git submodule update
	git config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
		while read path_key path; do
			#url_key=$(echo $path_key | sed 's/\.path/.url/')
			#url=$(git config -f .gitmodules --get "$url_key")
			#git submodule add $url $path
			echo "This is the submodule path: $path"
			echo "The following line is the command to checkout the submodule."
			echo "git submodule foreach --recursive 'git checkout-index -a -f --prefix=$SVNPATH/trunk/$path/'"
			git submodule foreach --recursive 'git checkout-index -a -f --prefix=$SVNPATH/trunk/$path/'
		done
fi

# Support for the /assets folder on the .org repo, locally this will be /.wordpress-org
echo "Moving assets."
# Make the directory if it doesn't already exist
mkdir -p $SVNPATH/assets/
mv $SVNPATH/trunk/.wordpress-org/* $SVNPATH/assets/
svn add --force $SVNPATH/assets/

echo

echo "Changing directory to SVN and committing to trunk."
cd $SVNPATH/trunk/
# Delete all files that should not now be added.
# Use $SVNIGNORE for `rm -rf`. Setting propset svn:ignore seems flaky.
echo "$SVNIGNORE" | awk '{print $0}' | xargs rm -rf
svn status | grep -v "^.[ \t]*\..*" | grep "^\!" | awk '{print $2"@"}' | xargs svn del
# Add all new files that are not set to be ignored
svn status | grep -v "^.[ \t]*\..*" | grep "^?" | awk '{print $2"@"}' | xargs svn add
svn commit --username=$PLUGIN_WORDPRESS_USER --password=$PLUGIN_WORDPRESS_PASSWORD -m "Preparing for $PLUGINVERSION release"

echo

echo "Updating WordPress plugin repo assets and committing."
cd $SVNPATH/assets/
# Delete all new files that are not set to be ignored
svn status | grep -v "^.[ \t]*\..*" | grep "^\!" | awk '{print $2"@"}' | xargs svn del
# Add all new files that are not set to be ignored
svn status | grep -v "^.[ \t]*\..*" | grep "^?" | awk '{print $2"@"}' | xargs svn add
svn update --quiet --accept working $SVNPATH/assets/*
svn resolve --accept working $SVNPATH/assets/*
svn commit --username=$PLUGIN_WORDPRESS_USER --password=$PLUGIN_WORDPRESS_PASSWORD -m "Updating assets"

echo

echo "Creating new SVN tag and committing it."
cd $SVNPATH
# If current tag not empty then update readme.txt
if [ -n "$(ls -A tags/$PLUGINVERSION 2>/dev/null)" ]; then
	echo "Updating readme.txt to tag $PLUGINVERSION"
	svn delete --force tags/$PLUGINVERSION/readme.txt
	svn copy trunk/readme.txt tags/$PLUGINVERSION
fi
svn copy --quiet trunk/ tags/$PLUGINVERSION/
# Remove trunk directories from tag directory
svn delete --force --quiet $SVNPATH/tags/$PLUGINVERSION/trunk
svn update --quiet --accept working $SVNPATH/tags/$PLUGINVERSION
#svn resolve --accept working $SVNPATH/tags/$PLUGINVERSION/*
cd $SVNPATH/tags/$PLUGINVERSION
svn commit --username=$PLUGIN_WORDPRESS_USER --password=$PLUGIN_WORDPRESS_PASSWORD -m "Tagging version $PLUGINVERSION"

echo "*** FIN ***"