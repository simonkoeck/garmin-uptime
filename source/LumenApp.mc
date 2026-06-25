using Toybox.Application as App;
using Toybox.WatchUi as Ui;

// Application entry point. A watch face only needs to hand back its view.
class LumenApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new LumenView() ];
    }

    // Re-render when the user changes field selections in Garmin Connect.
    function onSettingsChanged() {
        Ui.requestUpdate();
    }
}
