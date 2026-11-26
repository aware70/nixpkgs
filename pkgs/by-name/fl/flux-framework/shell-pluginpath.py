# Installed by the nixpkgs flux-framework package and run by flux-modprobe
# in rc1 on every broker.
#
# flux-shell searches only flux-core's own prefix for shell plugins, so
# plugins from other packages in the joined tree, such as flux-pmix, are
# not found. Point conf.shell_pluginpath at the joined tree instead, unless
# it was set to something else on the broker command line.


def setup(context):
    if context.attr_get("conf.shell_pluginpath") == "@corePluginPath@":
        context.handle.attr_set("conf.shell_pluginpath", "@pluginPath@")
