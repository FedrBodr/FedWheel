import Toybox.Attention;
import Toybox.Communications;
import Toybox.Lang;

function dataUpdateTimerMethod() {
    DataServer.updateData();
}

function appUpdateTimerMethod() {    
    /*
     * Updating comm_disconnectionCountdown runtime variable
     */
    if(AppStorage.runtimeDb["comm_lastResponseCode"] != 200) {
        AppStorage.runtimeDb["comm_disconnectionCountdown"]--;
    } else {
        AppStorage.runtimeDb["comm_disconnectionCountdown"] = 10;
    }

    /*
     * And checking whether the comm_disconnectionCountdown is finished:
     * phone lost -> waiting screen + one beep/vibration (only on connected -> not connected)
     */
    if (AppStorage.runtimeDb["comm_disconnectionCountdown"] == 0 && WheelData.isAppConnected) {
        WheelData.setIsAppConnected(false);
        Notify.tone(ToneProfiles.appDisconnectionTone);
        Notify.lostAlert();
    }

    if (WheelData.isAppConnected == false) {
        Communications.makeWebRequest(
            "http://127.0.0.1:" + WheelData.webServerPort + "/data/alarms",
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => {},
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            },
            new Lang.Method($, :timerMethods_reconnectionAttemptResponse)
        );
    }

    if (Attention has :playTone) {
        if (WheelData.batteryPercentage < 20 && WheelData.isWheelConnected) {
            AppStorage.runtimeDb["wheel_batteryLowToneCountdown"] = 30;
        }

        if (AppStorage.runtimeDb["wheel_batteryLowToneCountdown"] == 0) {
            Attention.playTone(ToneProfiles.wheelBatteryLowTone);
        }

    }

    /*
     * Wheel connected / disconnected: one tone per change, no repeats while the wheel stays off
     */
    var wheelChange = Notify.transition(AppStorage.runtimeDb["wheel_lastConnectionState"], WheelData.isWheelConnected);
    AppStorage.runtimeDb["wheel_lastConnectionState"] = WheelData.isWheelConnected;
    if (wheelChange == :connected) {
        Notify.tone(ToneProfiles.wheelConnectionTone);
    } else if (wheelChange == :disconnected) {
        Notify.tone(ToneProfiles.wheelDisconnectionTone);
        Notify.lostAlert();
    }
}

function timerMethods_reconnectionAttemptResponse(responseCode, data) {
    if (responseCode == 200) {
        WheelData.setIsAppConnected(true);
    }
}