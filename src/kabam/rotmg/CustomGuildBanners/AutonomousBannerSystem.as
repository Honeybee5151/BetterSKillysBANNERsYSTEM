package kabam.rotmg.CustomGuildBanners {
import com.company.assembleegameclient.game.MapUserInput;
import flash.events.KeyboardEvent;
import flash.display.Stage;
import flash.ui.Keyboard;

import kabam.rotmg.appengine.api.AppEngineClient;
import kabam.rotmg.core.StaticInjectorContext;

public class AutonomousBannerSystem {

    private static var _instance:AutonomousBannerSystem;
    private static var _stage:Stage;
    private static var _isActive:Boolean = false;

    // Banner dimensions (should match your BannerDrawSystem)
    private static const GRID_COLS:int = 20;
    private static const GRID_ROWS:int = 32;

    // Auto-detection settings
    private static var _autoSendOnSave:Boolean = false;
    private static var _keybindEnabled:Boolean = true;
    private static var _sendKey:uint = Keyboard.ENTER;

    private static var _lastPlayer:* = null; // store reference for keybind use

    /**
     * Initialize the autonomous banner system
     * @param stage The main stage reference
     */
    public static function initialize(stage:Stage):void {
        _stage = stage;

        if (!_instance) {
            _instance = new AutonomousBannerSystem();
        }

        // Start monitoring for banner operations
        startMonitoring();
    }

    /**
     * Start monitoring for banner save operations and keybinds
     */
    private static function startMonitoring():void {
        if (_stage && !_isActive) {
            _stage.addEventListener(KeyboardEvent.KEY_DOWN, onGlobalKeyDown);
            _isActive = true;
            trace("AutonomousBannerSystem: Monitoring started");
        }
    }

    /**
     * Stop monitoring
     */
    public static function stopMonitoring():void {
        if (_stage && _isActive) {
            _stage.removeEventListener(KeyboardEvent.KEY_DOWN, onGlobalKeyDown);
            _isActive = false;
            trace("AutonomousBannerSystem: Monitoring stopped");
        }
    }

    /**
     * Global key handler - works everywhere in the game
     */
    private static function onGlobalKeyDown(e:KeyboardEvent):void {
        // Only work when banner system is open
        if (!isBannerSystemOpen()) return;

        // Check for send banner keybind
        if (_keybindEnabled && e.keyCode == _sendKey) {
            sendCurrentBanner(_lastPlayer);
        }
    }

    /**
     * Check if banner system is currently open
     * Adapt this to your specific banner system detection
     */
    private static function isBannerSystemOpen():Boolean {
        // Method 1: Check your existing flag
        if (MapUserInput && MapUserInput.bannerSystemChecker) {
            return true;
        }

        // Method 2: Check if banner objects exist on stage (backup)
        try {
            for (var i:int = 0; i < _stage.numChildren; i++) {
                var child:* = _stage.getChildAt(i);
                if (child.hasOwnProperty("bannerSystemChecker") && child.bannerSystemChecker) {
                    return true;
                }
            }
        } catch (error:Error) {
            // Ignore errors in detection
        }

        return false;
    }

    /**
     * Send the currently saved banner to server.
     * Pass in the player object (map.player_) for correct guild detection.
     */
    private static function sendCurrentBanner(player:* = null):void {
        _lastPlayer = player; // Save for keybind use
        var guildName:String = getCurrentGuildName(player);
        sendSavedBannerToServer("playerBanner", guildName);
        trace("AutonomousBannerSystem: Sent banner for guild: " + guildName);
    }

    /**
     * Get the current player's guild name.
     * @param player Pass in the current player object (map.player_). Returns "Unknown Guild" if not available.
     */
    private static function getCurrentGuildName(player:* = null):String {
        try {
            if (player && player.guildName_ && player.guildName_ != "") {
                return player.guildName_;
            }
        } catch (error:Error) {
            trace("AutonomousBannerSystem: Could not auto-detect guild name");
        }
        return "Unknown Guild";
    }

    /**
     * Hook into banner save operations (call this from BannerStorage.saveBanner)
     */
    public static function onBannerSaved(slotName:String, player:* = null):void {
        if (_autoSendOnSave && isBannerSystemOpen()) {
            trace("AutonomousBannerSystem: Banner saved, auto-sending to server...");
            sendCurrentBanner(player);
        }
    }

    // === BANNER NETWORK FUNCTIONS (integrated) ===

    private static function convertArrayToString(bannerData:Array):String {
        if (!isValidBannerData(bannerData)) {
            trace("AutonomousBannerSystem: Invalid banner data, cannot convert");
            return "";
        }
        var dataString:String = "";
        for (var row:int = 0; row < GRID_ROWS; row++) {
            for (var col:int = 0; col < GRID_COLS; col++) {
                var colorValue:uint = bannerData[row][col];
                var hexColor:String = colorValue.toString(16).toUpperCase();
                while (hexColor.length < 6) {
                    hexColor = "0" + hexColor;
                }
                dataString += hexColor;
            }
        }
        return dataString;
    }

    private static function sendBannerToServer(bannerData:Array, guildName:String = ""):void {
        var bannerDataString:String = convertArrayToString(bannerData);

        if (bannerDataString == "") {
            trace("AutonomousBannerSystem: Cannot send invalid banner data");
            return;
        }

        // Get player credentials using the WebAccount system
        var credentials:Object = getPlayerCredentials();
        if (!credentials || !credentials.guid || !credentials.password) {
            trace("AutonomousBannerSystem: Cannot send banner - no authentication credentials");
            return;
        }

        var packetData:Object = {
            guid: credentials.guid,
            password: credentials.password,
            type: "CREATE_BANNER",
            bannerData: bannerDataString,
            width: GRID_COLS,
            height: GRID_ROWS
        };

        trace("AutonomousBannerSystem: Sending authenticated banner to server...");
        var client:AppEngineClient = StaticInjectorContext.getInjector().getInstance(AppEngineClient);
        client.sendRequest("/guild/setBanner", packetData);
    }

// Add this helper function to get player credentials
    // Add this import at the top with the other imports
    import kabam.rotmg.account.core.Account;

// Then replace the getPlayerCredentials function:
    private static function getPlayerCredentials():Object {
        try {
            // Get the account instance from the dependency injection system
            var account:Account = StaticInjectorContext.getInjector().getInstance(Account);

            if (account && account.isRegistered()) {
                var credentials:Object = account.getCredentials();
                trace("AutonomousBannerSystem: Retrieved credentials for user: " + credentials.guid);
                return credentials;
            } else {
                trace("AutonomousBannerSystem: Account not registered or not found");
                return null;
            }
        } catch (error:Error) {
            trace("AutonomousBannerSystem: Error getting credentials: " + error.message);
            return null;
        }
    }

    private static function sendSavedBannerToServer(slotName:String = "playerBanner", guildName:String = ""):void {
        var bannerData:Array = BannerStorage.loadBanner(slotName);
        if (bannerData == null) {
            trace("AutonomousBannerSystem: No saved banner found in slot '" + slotName + "'");
            return;
        }
        trace("AutonomousBannerSystem: Loaded banner from storage, sending to server...");
        sendBannerToServer(bannerData, guildName);
    }

    private static function isValidBannerData(bannerData:Array):Boolean {
        if (bannerData == null) return false;
        if (bannerData.length != GRID_ROWS) return false;
        for (var row:int = 0; row < bannerData.length; row++) {
            if (bannerData[row] == null || bannerData[row].length != GRID_COLS) return false;
            for (var col:int = 0; col < bannerData[row].length; col++) {
                var pixelValue:* = bannerData[row][col];
                if (!(pixelValue is Number) || pixelValue < 0 || pixelValue > 0xFFFFFF) {
                    return false;
                }
            }
        }
        return true;
    }

    // === Configuration methods ===

    public static function enableAutoSendOnSave(enabled:Boolean = true):void {
        _autoSendOnSave = enabled;
        trace("AutonomousBannerSystem: Auto-send on save: " + enabled);
    }



    /**
     * Manual send function (can be called from anywhere)
     * @param slotName The banner slot name
     * @param player The player object (map.player_) for correct guild
     */
    public static function sendBannerNow(slotName:String = "playerBanner", player:* = null):void {
        sendCurrentBanner(player);
    }

    /**
     * Get system status
     */
    public static function getStatus(player:* = null):Object {
        return {
            active: _isActive,
            bannerSystemOpen: isBannerSystemOpen(),
            autoSendOnSave: _autoSendOnSave,
            currentGuild: getCurrentGuildName(player)
        };
    }
}
}
