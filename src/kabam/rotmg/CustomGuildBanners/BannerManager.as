package kabam.rotmg.CustomGuildBanners {
import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.PixelSnapping;
import flash.display.Sprite;
import flash.events.Event;
import flash.geom.Matrix;
import flash.utils.getTimer;
import flash.utils.setTimeout;

import com.company.assembleegameclient.game.MapUserInput;
import com.company.assembleegameclient.map.Map;

import kabam.rotmg.CustomGuildBanners.AutonomousBannerSystem;
import kabam.rotmg.CustomGuildBanners.BannerDrawSystem;
import kabam.rotmg.CustomGuildBanners.ColorPicker;
import kabam.rotmg.CustomGuildBanners.SimpleButton;
import kabam.rotmg.CustomGuildBanners.BannerStorage;

public class BannerManager extends Sprite {

    // UI Components
    private var CP:ColorPicker;
    private var BDS:BannerDrawSystem;
    public var bannerData:Array;

    // Buttons
    private var saveButton:SimpleButton;
    private var clearButton:SimpleButton;
    private var loadButton:SimpleButton;
    private var exitButton:SimpleButton;
    private var exportButton:SimpleButton;

    // Export cooldown management
    private var lastExportTime:Number = 0;
    private var exportCooldown:Number = 10000; // 10 seconds cooldown
    private var exportButtonOriginalText:String = "Export to Server";

    // Reference to the game map (needed for player access)
    private var gameMap:Map;

    public function BannerManager(map:Map) {
        this.gameMap = map;
        initializeComponents();
    }

    private function initializeComponents():void {
        try {
            // Initialize banner system components
            CP = new ColorPicker();
            BDS = new BannerDrawSystem();
            BDS.y = 15;

            // Set up the color picker connection
            if (CP && BDS) {
                BDS.setColorPicker(CP);
            }

            trace("BannerManager: Components initialized successfully");
        } catch (error:Error) {
            trace("BannerManager: Error initializing components: " + error.message);
            CP = null;
            BDS = null;
        }
    }

    public function bannerSystemAdd():void {
        if (stage) {
            stage.stageFocusRect = false;
        } else {
            this.addEventListener(Event.ADDED_TO_STAGE, function (e:Event):void {
                stage.stageFocusRect = false;
            });
        }

        // Ensure components are initialized
        if (!CP || !BDS) {
            trace("BannerManager: Components not initialized, reinitializing...");
            initializeComponents();
        }

        // Add main components with null checks
        if (CP) {
            addChild(CP);
        } else {
            trace("BannerManager: Error - ColorPicker is null!");
            return;
        }

        if (BDS) {
            addChild(BDS);
        } else {
            trace("BannerManager: Error - BannerDrawSystem is null!");
            return;
        }

        // Create and position buttons
        createButtons();
        positionButtons();
        addButtonListeners();
        addButtonsToStage();

        // Set the banner system checker flag
        MapUserInput.bannerSystemChecker = true;
    }

    private function createButtons():void {
        saveButton = new SimpleButton("Save Banner", 120, 35);
        clearButton = new SimpleButton("Clear", 80, 35);
        loadButton = new SimpleButton("Load", 80, 35);
        exitButton = new SimpleButton("Exit", 80, 35);
        exportButton = new SimpleButton(exportButtonOriginalText, 130, 35);
    }

    private function positionButtons():void {
        saveButton.x = 30;
        saveButton.y = 250;

        clearButton.x = 30;
        clearButton.y = 500;

        loadButton.x = 30;
        loadButton.y = 300;

        exitButton.x = 30;
        exitButton.y = 550;

        exportButton.x = 30;
        exportButton.y = 350;
    }

    private function addButtonListeners():void {
        saveButton.addEventListener("buttonClicked", onSaveClicked);
        clearButton.addEventListener("buttonClicked", onClearClicked);
        loadButton.addEventListener("buttonClicked", onLoadClicked);
        exportButton.addEventListener("buttonClicked", onExportClicked);
        exitButton.addEventListener("buttonClicked", onExitClicked);
    }

    private function addButtonsToStage():void {
        if (saveButton) addChild(saveButton);
        if (clearButton) addChild(clearButton);
        if (loadButton) addChild(loadButton);
        if (exportButton) addChild(exportButton);
        if (exitButton) addChild(exitButton);
    }

    private function onExitClicked(e:Event):void {
        bannerSystemRemove();
        trace("Banner UI closed");

        // Dispatch event to parent to handle cleanup
        dispatchEvent(new Event("bannerSystemClosed"));
    }

    private function onSaveClicked(e:Event):void {
        bannerData = BDS.getBannerData();

        // Save to persistent storage
        if (BannerStorage.saveBanner(bannerData, "playerBanner")) {
            trace("Banner saved successfully!");

            // Trigger autonomous system hook for auto-send feature
            AutonomousBannerSystem.onBannerSaved("playerBanner", gameMap ? gameMap.player_ : null);
        } else {
            trace("Failed to save banner");
        }
    }

    private function onClearClicked(e:Event):void {
        // Clear the banner
        BDS.clearBanner();
        trace("Banner cleared");
    }

    private function onLoadClicked(e:Event):void {
        // Load from persistent storage
        var loadedData:Array = BannerStorage.loadBanner("playerBanner");

        if (loadedData != null) {
            BDS.loadBannerData(loadedData);
            bannerData = loadedData; // Update local copy too
            trace("Banner loaded successfully!");
        } else {
            trace("No saved banner found");
        }
    }

    private function onExportClicked(e:Event):void {
        var currentTime:Number = getTimer();

        // Check if still on cooldown
        if (currentTime - lastExportTime < exportCooldown) {
            var remainingTime:Number = Math.ceil((exportCooldown - (currentTime - lastExportTime)) / 1000);
            trace("Export cooldown: " + remainingTime + " seconds remaining");
            return; // Exit early - don't export
        }

        // Auto-save current banner before exporting
        bannerData = BDS.getBannerData();
        BannerStorage.saveBanner(bannerData, "playerBanner");

        // Export banner to server
        if (gameMap && gameMap.player_) {
            // Clear cache so updated banner will be fetched next time
            ClientBannerRendering.clearBannerCache();

            AutonomousBannerSystem.sendBannerNow("playerBanner", gameMap.player_);
            trace("Auto-saved, cleared cache, and exporting banner to server...");

            // Start simple cooldown
            startExportButtonCooldown();
        } else {
            trace("Cannot export: No player reference available");
        }
    }

    private function startExportButtonCooldown():void {
        lastExportTime = getTimer();

        // Just disable button for 10 seconds - no fancy countdown
        exportButton.enabled = false;
        exportButton.text = "Please wait...";

        // Simple timer to re-enable
        setTimeout(function ():void {
            if (exportButton) { // Check if button still exists
                exportButton.enabled = true;
                exportButton.text = exportButtonOriginalText;
            }
        }, exportCooldown);
    }

    public function bannerSystemRemove():void {
        // Remove all banner UI elements with null checks
        if (CP && contains(CP)) removeChild(CP);
        if (BDS && contains(BDS)) removeChild(BDS);
        if (saveButton && contains(saveButton)) removeChild(saveButton);
        if (clearButton && contains(clearButton)) removeChild(clearButton);
        if (loadButton && contains(loadButton)) removeChild(loadButton);
        if (exportButton && contains(exportButton)) removeChild(exportButton);
        if (exitButton && contains(exitButton)) removeChild(exitButton);

        // Clear the banner system checker flag
        MapUserInput.bannerSystemChecker = false;

        // Clean up references
        cleanup();
    }

    private function cleanup():void {
        // Remove event listeners to prevent memory leaks
        if (saveButton) {
            saveButton.removeEventListener("buttonClicked", onSaveClicked);
            saveButton = null;
        }
        if (clearButton) {
            clearButton.removeEventListener("buttonClicked", onClearClicked);
            clearButton = null;
        }
        if (loadButton) {
            loadButton.removeEventListener("buttonClicked", onLoadClicked);
            loadButton = null;
        }
        if (exportButton) {
            exportButton.removeEventListener("buttonClicked", onExportClicked);
            exportButton = null;
        }
        if (exitButton) {
            exitButton.removeEventListener("buttonClicked", onExitClicked);
            exitButton = null;
        }

        // Clear other references
        CP = null;
        BDS = null;
        bannerData = null;
        gameMap = null;
    }

    // Public getters for external access if needed
    public function getBannerDrawSystem():BannerDrawSystem {
        return BDS;
    }

    public function getColorPicker():ColorPicker {
        return CP;
    }

    public function getCurrentBannerData():Array {
        return bannerData;
    }

    // Method to update the map reference if needed
    public function updateMapReference(map:Map):void {
        this.gameMap = map;
    }

    public function handleBannerNetworkResponse(response:Object, endpoint:String):void {
        if (endpoint && endpoint.indexOf("getGuildBanner") >= 0) {
            trace("Manager: Banner network response received (handled by queue system)");
            // Don't call BannerRetrievalSystem.handleBannerResponse - queue handles it now
        }
    }

    public function displayGuildBanner(guildId:int, container:*, x:Number = 0, y:Number = 0, size:int = 16):void {
        BannerRetrievalSystem.displayBannerAt(guildId, container, x, y, size, getCurrentPlayer());
    }

    public function displayPlayerBanner(container:*, x:Number = 0, y:Number = 0, size:int = 24):void {
        var player:* = getCurrentPlayer();
        if (player) {
            try {
                var guildId:int = player.guildId_ || 0;
                if (guildId > 0) {
                    displayGuildBanner(guildId, container, x, y, size);
                } else {
                    trace("Manager: Player is not in a guild");
                }
            } catch (error:Error) {
                trace("Manager: Error getting player guild ID - " + error.message);
            }
        }
    }

    public function displayMultipleGuildBanners(guildIds:Array, callback:Function, size:int = 16):void {
        BannerRetrievalSystem.requestMultipleBanners(guildIds, callback, size, getCurrentPlayer());
    }

    /**
     * Clean up banner systems
     */
    public function cleanupBannerSystems():void {
        trace("Manager: Cleaning up banner systems...");
        try {
            BannerRetrievalSystem.cancelAllRequests();
            ClientBannerRendering.clearBannerCache();
        } catch (error:Error) {
            trace("Manager: Error during banner cleanup - " + error.message);
        }
    }

    /**
     * Get banner system status for debugging
     */
    public function getBannerSystemStatus():Object {
        return {
            retrievalStatus: BannerRetrievalSystem.getStatus(),
            cacheStatus: ClientBannerRendering.getCacheStats()
        };
    }

// Helper method - adapt this to however your manager gets the current player
    private function getCurrentPlayer():* {
        // Replace this with however your manager accesses the current player
        return gameMap ? gameMap.player_ : null; // or however you get the player reference
    }

    /**
     * Create a banner object instead of just displaying the bitmap
     * @param guildId Guild ID to get banner for
     * @param x X position for the banner object
     * @param y Y position for the banner object
     * @param callback Optional callback when banner object is created
     */

    public function createRotMGBannerInWorld(guildId:int, x:Number, y:Number):void {
        // Request the banner bitmap directly at pixelSize = 6 (or your desired scale)
        BannerRetrievalSystem.requestGuildBanner(guildId, function(bannerBitmap:Bitmap, receivedGuildId:int):void {
            if (bannerBitmap) {
                bannerBitmap.smoothing = false;
                bannerBitmap.pixelSnapping = PixelSnapping.ALWAYS;

                // Do NOT scale the bitmap instance
                bannerBitmap.scaleX = 1;
                bannerBitmap.scaleY = 1;

                // Snap to integer pixel positions (no division needed since bitmap is already scaled)
                bannerBitmap.x = Math.round(x);
                bannerBitmap.y = Math.round(y);

                if (gameMap) {
                    gameMap.addChild(bannerBitmap);
                }

                trace("Created banner at world pos (" + bannerBitmap.x + "," + bannerBitmap.y + ")");
            }
        }, 6, getCurrentPlayer()); // pixelSize = 6 - generate scaled bitmap
    }
}
}