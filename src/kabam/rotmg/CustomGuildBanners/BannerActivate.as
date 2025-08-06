package kabam.rotmg.CustomGuildBanners {
import com.company.assembleegameclient.objects.Player;
import com.company.assembleegameclient.objects.ObjectLibrary;

import flash.display.BitmapData;
import flash.events.TimerEvent;
import flash.geom.Rectangle;
import flash.utils.Dictionary;
import flash.utils.Timer;

import kabam.rotmg.messaging.impl.GameServerConnection;

/**
 * Banner system that integrates with GameServerConnection and creates custom textures
 * Works with your GuildBanner class to display guild-specific banners
 */
public class BannerActivate {

    private static var _instance:BannerActivate;
    private static var _bannerInstanceMap:Dictionary = new Dictionary();

    // IMPORTANT: This must match the _pendingBanners referenced in GameServerConnection
    public static var _pendingBanners:Array = [];

    // Store persistent banner data that survives entity recreation
    private static var _persistentBannerData:Dictionary = new Dictionary(); // entityId -> bannerData

    public function BannerActivate() {
        _instance = this;
        trace("BannerActivate: Guild banner system initialized with texture creation");
    }

    public static function getInstance():BannerActivate {
        if (!_instance) {
            _instance = new BannerActivate();
        }
        return _instance;
    }

    // ====== MAIN ENTITY MAPPING SYSTEM ======
    // Called from GameServerConnection.handleBannerActivationNotification

    public static function mapEntityToBanner(entityId:int, guildId:int, instanceId:String):void {
        try {
            trace("BannerActivate: Mapping entity " + entityId + " to guild " + guildId + " banner");

            // Simple banner data - just store the guild ID
            var bannerData:Object = {
                entityId: entityId,
                guildId: guildId,
                instanceId: instanceId,
                timestamp: new Date().time
                // Don't store hex data - always fetch fresh from BulkBannerSystem
            };

            _persistentBannerData[entityId.toString()] = bannerData;
            _bannerInstanceMap[entityId.toString()] = bannerData;

            // Apply immediately or queue
            var success:Boolean = applyBannerToEntity(entityId, bannerData);
            if (!success) {
                _pendingBanners.push({
                    entityId: entityId,
                    guildId: guildId,
                    instanceId: instanceId
                });
            }

        } catch (error:Error) {
            trace("BannerActivate: Error mapping entity - " + error.message);
        }
    }

    // ====== BANNER APPLICATION TO INDIVIDUAL ENTITIES ======

    public static function applyBannerToEntity(entityId:int, bannerData:Object):Boolean {
        try {
            trace("BannerActivate: Applying banner to entity " + entityId);

            var gameEntity:* = findEntityInWorld(entityId);
            if (!gameEntity) {
                trace("BannerActivate: Entity " + entityId + " not found in world");
                return false;
            }

            trace("BannerActivate: Found entity " + entityId + ", type: " + gameEntity.constructor.toString());

            // Apply custom banner texture to the entity
            return applyCustomBannerTexture(gameEntity, bannerData);

        } catch (error:Error) {
            trace("BannerActivate: Error applying banner to entity " + entityId + " - " + error.message);
            return false;
        }
    }

    // ====== CUSTOM TEXTURE APPLICATION ======

    private static function applyCustomBannerTexture(gameEntity:*, bannerData:Object):Boolean {
        try {
            trace("BannerActivate: Creating texture for guild " + bannerData.guildId + " banner");

            var guildTexture:BitmapData;

            // Always get fresh data from BulkBannerSystem based on guild ID
            var guildId:int = bannerData.guildId;

            if (BulkBannerSystem.hasBanner(guildId)) {
                var hexData:String = BulkBannerSystem.getHexData(guildId);

                if (hexData && hexData.length > 100) {
                    trace("BannerActivate: Rendering guild " + guildId + " banner from BulkBannerSystem (length: " + hexData.length + ")");
                    guildTexture = renderBannerFromHexString(hexData);
                } else {
                    trace("BannerActivate: Guild " + guildId + " has invalid hex data in BulkBannerSystem");
                }
            } else {
                trace("BannerActivate: Guild " + guildId + " has no banner in BulkBannerSystem");
            }

            // Use fallback if we couldn't get real data
            if (!guildTexture) {
                trace("BannerActivate: Using fallback texture for guild " + guildId);
                guildTexture = createFallbackBannerTexture();
            }

            // Apply to entity
            gameEntity.customBannerTexture_ = guildTexture;
            gameEntity.hasCustomBanner_ = true;
            gameEntity.guildId_ = guildId;

            trace("BannerActivate: Applied banner to entity " + gameEntity.objectId_);
            forceEntityRefresh(gameEntity);

            return true;

        } catch (error:Error) {
            trace("BannerActivate: Error applying texture - " + error.message);
            return false;
        }
    }
    // ====== TEXTURE CREATION ======

    private static function createGuildBannerTexture(guildHexData:String):BitmapData {
        try {
            trace("BannerActivate: Creating banner texture from guild data: " + guildHexData.substring(0, 100) + "..."); // Truncate for readability

            // The guildHexData is actually the pixel data, not just colors
            var texture:BitmapData = renderBannerFromHexString(guildHexData);

            if (!texture) {
                trace("BannerActivate: Failed to render from hex string, using fallback");
                return createFallbackBannerTexture();
            }

            trace("BannerActivate: Created guild banner texture " + texture.width + "x" + texture.height);
            return texture;

        } catch (error:Error) {
            trace("BannerActivate: Error creating guild banner texture - " + error.message);
            return createFallbackBannerTexture();
        }
    }

    private static function renderBannerFromHexString(hexData:String):BitmapData {
        try {
            // Assuming the hex string represents 64x64 pixels (4096 pixels total)
            // Each pixel is represented by 6 hex characters (RRGGBB)
            var textureSize:int = 64;
            var expectedLength:int = textureSize * textureSize * 6; // 64x64x6 = 24576 characters

            trace("BannerActivate: Hex data length: " + hexData.length + ", expected: " + expectedLength);

            var texture:BitmapData = new BitmapData(textureSize, textureSize, true, 0x00000000);

            // Process the hex string pixel by pixel
            var hexIndex:int = 0;

            for (var y:int = 0; y < textureSize; y++) {
                for (var x:int = 0; x < textureSize; x++) {

                    // Make sure we don't go past the end of the hex string
                    if (hexIndex + 6 > hexData.length) {
                        // Fill remaining pixels with transparent
                        texture.setPixel32(x, y, 0x00000000);
                        continue;
                    }

                    // Extract 6 characters for this pixel (RRGGBB)
                    var pixelHex:String = hexData.substr(hexIndex, 6);
                    hexIndex += 6;

                    // Convert to color value
                    var color:uint;
                    if (pixelHex == "000000") {
                        // Transparent pixel
                        color = 0x00000000;
                    } else {
                        // Opaque pixel with RGB value
                        color = uint("0xFF" + pixelHex);
                    }

                    // Set the pixel
                    texture.setPixel32(x, y, color);
                }
            }

            trace("BannerActivate: Rendered " + (hexIndex / 6) + " pixels from hex data");
            return texture;

        } catch (error:Error) {
            trace("BannerActivate: Error rendering from hex string - " + error.message);
            return null;
        }
    }

    private static function renderDiamondPattern(texture:BitmapData, startY:int, height:int, accentColor:uint):void {
        try {
            var width:int = texture.width;
            var centerX:int = width / 2;
            var centerY:int = startY + (height / 2);
            var diamondSize:int = Math.min(width, height) / 4;

            // Create diamond shape in center
            for (var x:int = 0; x < width; x++) {
                for (var y:int = startY; y < startY + height; y++) {
                    var dx:int = Math.abs(x - centerX);
                    var dy:int = Math.abs(y - centerY);

                    if (dx + dy < diamondSize) {
                        texture.setPixel32(x, y, accentColor);
                    }
                }
            }

        } catch (error:Error) {
            trace("BannerActivate: Error rendering diamond pattern - " + error.message);
        }
    }

    private static function addBannerBorder(texture:BitmapData):void {
        try {
            var width:int = texture.width;
            var height:int = texture.height;
            var borderColor:uint = 0xFF000000; // Black border
            var borderThickness:int = 2;

            // Draw border around entire texture
            texture.fillRect(new Rectangle(0, 0, width, borderThickness), borderColor); // Top
            texture.fillRect(new Rectangle(0, height - borderThickness, width, borderThickness), borderColor); // Bottom
            texture.fillRect(new Rectangle(0, 0, borderThickness, height), borderColor); // Left
            texture.fillRect(new Rectangle(width - borderThickness, 0, borderThickness, height), borderColor); // Right

        } catch (error:Error) {
            trace("BannerActivate: Error adding border - " + error.message);
        }
    }

    private static function parseGuildColorsFromHexData(hexData:String):Array {
        var colors:Array = [];

        try {
            // Handle different formats: "FF0000,00FF00,0000FF" or "FF0000FF00000000FF"
            var colorStrings:Array;

            if (hexData.indexOf(",") !== -1 || hexData.indexOf("|") !== -1) {
                // Comma or pipe separated
                colorStrings = hexData.split(/[,|]/);
            } else {
                // Continuous hex string - split every 6 characters
                colorStrings = [];
                for (var i:int = 0; i < hexData.length; i += 6) {
                    if (i + 6 <= hexData.length) {
                        colorStrings.push(hexData.substr(i, 6));
                    }
                }
            }

            // Convert hex strings to color values
            for each (var colorStr:String in colorStrings) {
                var cleanHex:String = colorStr.replace(/[#\s]/g, ""); // Remove # and spaces
                if (cleanHex.length >= 6) {
                    var color:uint = uint("0xFF" + cleanHex.substr(0, 6));
                    colors.push(color);
                }

                if (colors.length >= 6) break; // Limit to 6 colors
            }

            trace("BannerActivate: Parsed " + colors.length + " colors from hex data");

        } catch (error:Error) {
            trace("BannerActivate: Error parsing guild colors - " + error.message);
        }

        // Ensure we have at least 3 colors with fallbacks
        while (colors.length < 3) {
            if (colors.length == 0) colors.push(0xFFFF0000); // Red
            else if (colors.length == 1) colors.push(0xFF00FF00); // Green
            else colors.push(0xFF0000FF); // Blue
        }

        return colors;
    }

    private static function createFallbackBannerTexture():BitmapData {
        try {
            var texture:BitmapData = new BitmapData(64, 64, true, 0x00000000);

            // Create simple red/white/blue fallback banner
            texture.fillRect(new Rectangle(0, 0, 64, 21), 0xFFFF0000); // Red top
            texture.fillRect(new Rectangle(0, 21, 64, 22), 0xFFFFFFFF); // White middle
            texture.fillRect(new Rectangle(0, 43, 64, 21), 0xFF0000FF); // Blue bottom

            trace("BannerActivate: Created fallback banner texture");
            return texture;

        } catch (error:Error) {
            trace("BannerActivate: Error creating fallback texture - " + error.message);
            return new BitmapData(64, 64, false, 0xFF808080); // Gray fallback
        }
    }

    // ====== ENTITY REFRESH ======

    private static function forceEntityRefresh(gameEntity:*):void {
        try {
            // Force the entity to redraw with new texture
            if (gameEntity.hasOwnProperty("invalidate") && gameEntity.invalidate is Function) {
                gameEntity.invalidate();
                trace("BannerActivate: Called entity.invalidate()");
            }

            if (gameEntity.square_) {
                if (gameEntity.square_.hasOwnProperty("invalidate") && gameEntity.square_.invalidate is Function) {
                    gameEntity.square_.invalidate();
                    trace("BannerActivate: Called square.invalidate()");
                }
            }

            // Force position update to trigger redraw
            if (gameEntity.hasOwnProperty("x_") && gameEntity.hasOwnProperty("y_")) {
                var oldX:Number = gameEntity.x_;
                var oldY:Number = gameEntity.y_;
                gameEntity.x_ = oldX + 0.001;
                gameEntity.y_ = oldY + 0.001;
                gameEntity.x_ = oldX;
                gameEntity.y_ = oldY;
            }

        } catch (error:Error) {
            trace("BannerActivate: Error refreshing entity - " + error.message);
        }
    }

    // ====== PERSISTENT DATA MANAGEMENT ======

    /**
     * Get persistent banner data for an entity (survives entity recreation)
     */
    public static function getBannerDataForEntity(entityId:int):Object {
        return _persistentBannerData[entityId.toString()];
    }

    /**
     * Check if entity should have a banner applied (for entity recreation)
     */
    public static function shouldApplyBanner(entityId:int):Boolean {
        return _persistentBannerData.hasOwnProperty(entityId.toString());
    }

    /**
     * Apply banner when entity is recreated (called from GameServerConnection.addObject)
     */
    public static function applyBannerOnEntityCreation(gameEntity:*):void {
        try {
            if (!gameEntity || !gameEntity.hasOwnProperty("objectId_")) {
                return;
            }

            var entityId:int = gameEntity.objectId_;
            var bannerData:Object = getBannerDataForEntity(entityId);

            if (bannerData) {
                trace("BannerActivate: Applying banner to recreated entity " + entityId);
                applyBannerToEntity(entityId, bannerData);
            }

        } catch (error:Error) {
            trace("BannerActivate: Error applying banner on entity creation - " + error.message);
        }
    }

    // ====== UTILITY METHODS ======

    private static function findEntityInWorld(entityId:int):* {
        try {
            var gameScreen:* = GameServerConnection.instance.gs_;
            if (gameScreen && gameScreen.map && gameScreen.map.goDict_) {
                return gameScreen.map.goDict_[entityId];
            }
            return null;
        } catch (error:Error) {
            return null;
        }
    }

    // ====== INTEGRATION METHODS FOR GAMESERVERCONNECTION ======

    public static function processPendingBanner(entityId:int, guildId:int):Boolean {
        try {
            trace("BannerActivate: Processing pending banner - entity " + entityId + ", guild " + guildId);

            // Create simple banner data with just guild ID
            var bannerData:Object = {
                entityId: entityId,
                guildId: guildId,
                instanceId: "pending_" + entityId
            };

            _persistentBannerData[entityId.toString()] = bannerData;

            // The applyBannerToEntity will handle looking up guild data
            return applyBannerToEntity(entityId, bannerData);

        } catch (error:Error) {
            trace("BannerActivate: Error processing pending banner - " + error.message);
            return false;
        }
    }

    public static function matchesPendingBanner(actualEntityId:int, pendingEntityId:int):Boolean {
        return actualEntityId == pendingEntityId ||
                actualEntityId == pendingEntityId + 1 ||
                actualEntityId == pendingEntityId - 1;
    }

    public static function removeEntityMapping(entityId:int):void {
        try {
            var entityKey:String = entityId.toString();

            // Remove from active mappings
            if (_bannerInstanceMap[entityKey]) {
                delete _bannerInstanceMap[entityKey];
            }

            // Remove from persistent data (banner is gone)
            if (_persistentBannerData[entityKey]) {
                delete _persistentBannerData[entityKey];
                trace("BannerActivate: Removed persistent banner data for entity " + entityId);
            }

            // Remove from pending queue
            for (var i:int = _pendingBanners.length - 1; i >= 0; i--) {
                if (_pendingBanners[i].entityId == entityId) {
                    _pendingBanners.splice(i, 1);
                    break;
                }
            }
        } catch (error:Error) {
            trace("BannerActivate: Error removing entity mapping - " + error.message);
        }
    }

    // ====== ACTIVATION METHODS ======

    public function activate(player:Player, item:*):Boolean {
        try {
            var guildId:int = getPlayerGuildId(player);
            if (guildId <= 0) {
                showMessage(player, "You must be in a guild to place banners!");
                return false;
            }

            if (!BulkBannerSystem.hasBanner(guildId)) {
                showMessage(player, "Guild banner data not available!");
                return false;
            }

            showMessage(player, "Placing guild banner...");
            return true;

        } catch (error:Error) {
            return false;
        }
    }

    private function getPlayerGuildId(player:Player):int {
        return 1; // TODO: Get from guild system
    }

    private function showMessage(player:Player, message:String):void {
        trace("Message to " + player.name_ + ": " + message);
    }

    // ====== DEBUG METHODS ======

    public static function debugEntityBanner(entityId:int):void {
        try {
            var entity:* = findEntityInWorld(entityId);
            if (!entity) {
                trace("Entity " + entityId + " not found");
                return;
            }

            trace("*** Banner Debug for Entity " + entityId + " ***");
            trace("Entity type: " + entity.constructor.toString());
            trace("hasCustomBanner_: " + entity.hasCustomBanner_);
            trace("guildId_: " + entity.guildId_);

            if (entity.customBannerTexture_) {
                var texture:BitmapData = entity.customBannerTexture_;
                trace("customBannerTexture_: " + texture.width + "x" + texture.height);
            } else {
                trace("customBannerTexture_: null");
            }

            var bannerData:Object = getBannerDataForEntity(entityId);
            if (bannerData) {
                trace("Persistent banner data found:");
                trace("  Guild ID: " + bannerData.guildId);
                trace("  Colors: " + bannerData.guildColors);
            } else {
                trace("No persistent banner data");
            }

        } catch (error:Error) {
            trace("Debug failed: " + error.message);
        }
    }

    public static function testConnection():void {
        trace("*** BannerActivate.testConnection() - GUILD BANNER SYSTEM READY ***");
        trace("Persistent banner data entries: " + getPersistentDataCount());
        trace("Pending banners: " + _pendingBanners.length);

        // Test BulkBannerSystem connection
        try {
            var testData:String = BulkBannerSystem.getHexData(1);
            trace("BulkBannerSystem connection test: " + (testData ? "SUCCESS" : "FAILED"));
        } catch (e:Error) {
            trace("BulkBannerSystem connection test: ERROR - " + e.message);
        }
    }

    private static function getPersistentDataCount():int {
        var count:int = 0;
        for (var key:String in _persistentBannerData) {
            count++;
        }
        return count;
    }

    // ====== CLEAR/RESET METHODS ======

    public static function clearAllBannerData():void {
        try {
            _persistentBannerData = new Dictionary();
            _bannerInstanceMap = new Dictionary();
            _pendingBanners = [];
            trace("BannerActivate: Cleared all banner data");
        } catch (error:Error) {
            trace("BannerActivate: Error clearing data - " + error.message);
        }
    }
    private static function requestGuildBannerAndRetry(entityId:int, guildId:int, instanceId:String):void {
        trace("BannerActivate: Requesting banner for guild " + guildId + " from server...");

        BannerRetrievalSystem.requestGuildBanner(guildId, function(bannerShape:*, receivedGuildId:int):void {
            trace("BannerActivate: Received response for guild " + receivedGuildId);

            // The BannerRetrievalSystem should have stored the data in BulkBannerSystem
            // Now retry the banner application
            setTimeout(function():void {
                trace("BannerActivate: Retrying banner application for entity " + entityId);
                mapEntityToBanner(entityId, guildId, instanceId);
            }, 100); // Small delay to ensure storage is complete

        }, 16); // pixelSize parameter
    }

// Helper timeout function if you don't have it
    private static function setTimeout(callback:Function, delay:int):void {
        var timer:Timer = new Timer(delay, 1);
        timer.addEventListener(TimerEvent.TIMER_COMPLETE, function(e:TimerEvent):void {
            callback();
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE, arguments.callee);
        });
        timer.start();
    }


}
}