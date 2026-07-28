// Wayland windows spawn with no activity assignment (= visible on all
// activities). Bind unassigned new normal windows to the current activity.
// Windows explicitly set to "All Activities" later are not touched — this
// only runs once, at window creation.
workspace.windowAdded.connect(function (w) {
    if (w.normalWindow && w.activities.length === 0) {
        w.activities = [workspace.currentActivity];
    }
});
