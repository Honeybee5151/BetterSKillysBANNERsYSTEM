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
            // Original banner dimensions from data
            var bannerWidth:int = 20;
            var bannerHeight:int = 32;

            // Scale factor to make pixels bigger
            var pixelScale:int = 5;

            // Pole dimensions (in game pixels)
            var poleWidth:int = 2; // 2 pixels wide
            var poleExtension:int = 16; // Extends 16 pixels below banner

            // Final scaled dimensions
            var scaledBannerWidth:int = bannerWidth * pixelScale;
            var scaledBannerHeight:int = bannerHeight * pixelScale;
            var scaledPoleWidth:int = poleWidth * pixelScale;
            var scaledPoleExtension:int = poleExtension * pixelScale;

            // Total texture size - banner width stays same, height includes pole extension
            var totalWidth:int = scaledBannerWidth; // Just banner width
            var totalHeight:int = scaledBannerHeight + scaledPoleExtension; // Banner + pole extension

            var expectedLength:int = bannerWidth * bannerHeight * 6; // 20x32x6 = 3840 characters

            trace("BannerActivate: Creating banner with pole underneath - Banner: " + scaledBannerWidth + "x" + scaledBannerHeight + ", Total: " + totalWidth + "x" + totalHeight + " (scale: " + pixelScale + "x)");
            trace("BannerActivate: Hex data length: " + hexData.length + ", expected: " + expectedLength);

            var texture:BitmapData = new BitmapData(totalWidth, totalHeight, true, 0x00000000);

            // Process banner data pixel by pixel for the top portion
            var hexIndex:int = 0;

            for (var gameY:int = 0; gameY < bannerHeight; gameY++) {
                for (var gameX:int = 0; gameX < bannerWidth; gameX++) {

                    // Get banner pixel color
                    var bannerColor:uint = 0x00000000; // Default transparent

                    if (hexIndex + 6 <= hexData.length) {
                        var pixelHex:String = hexData.substr(hexIndex, 6);
                        hexIndex += 6;

                        if (pixelHex != "000000") {
                            bannerColor = uint("0xFF" + pixelHex);
                        }
                    }

                    // Render this game pixel as a scaled block in the banner area
                    renderScaledPixel(texture, gameX * pixelScale, gameY * pixelScale, pixelScale, bannerColor);
                }
            }

            // Now render the pole under the right side of the banner
            renderPoleUnderBanner(texture, bannerWidth, bannerHeight, poleWidth, poleExtension, pixelScale);
            trace("BannerActivate: Rendered banner with pole support underneath");
            return texture;

        } catch (error:Error) {
            trace("BannerActivate: Error rendering banner with pole - " + error.message);
            return createFallbackBannerWithPole();
        }
    }

    private static function renderScaledPixel(texture:BitmapData, startX:int, startY:int, scale:int, color:uint):void {
        try {
            // Fill a scale x scale block with the pixel color
            for (var dy:int = 0; dy < scale; dy++) {
                for (var dx:int = 0; dx < scale; dx++) {
                    var pixelX:int = startX + dx;
                    var pixelY:int = startY + dy;

                    if (pixelX >= 0 && pixelX < texture.width && pixelY >= 0 && pixelY < texture.height) {
                        texture.setPixel32(pixelX, pixelY, color);
                    }
                }
            }
        } catch (error:Error) {
            trace("BannerActivate: Error rendering scaled pixel - " + error.message);
        }
    }

    private static function renderPoleUnderBanner(texture:BitmapData, bannerWidth:int, bannerHeight:int, poleWidth:int, poleExtension:int, pixelScale:int):void {
        try {
            // Brown colors for wood texture
            var brownColors:Array = [
                0xFF8B4513,  // Dark brown
                0xFF654321,  // Very dark brown
                0xFF4A2C17,  // Darker brown
                0xFF2F1B14
            ];

            // Calculate pole position - under the right side of banner
            var poleStartX:int = ((bannerWidth - poleWidth) / 2) * pixelScale; // Right side minus pole width
            var poleStartY:int = (bannerHeight * pixelScale) + pixelScale;// Starts where banner ends

            trace("BannerActivate: Rendering pole at position (" + poleStartX + ", " + poleStartY + ") size " + (poleWidth * pixelScale) + "x" + (poleExtension * pixelScale));

            // Render pole extending downward
            for (var gameX:int = 0; gameX < poleWidth; gameX++) {
                for (var gameY:int = 0; gameY < poleExtension; gameY++) {
                    var color:uint;

                    // Create wood grain pattern
                    if (gameX == 0) {
                        // Left edge of pole - darker (shadow side)
                        color = (gameY % 3 == 0) ? brownColors[3] : brownColors[2];
                    } else {
                        // Right edge of pole - lighter (highlight side)
                        color = (gameY % 4 == 0) ? brownColors[0] : brownColors[1];
                    }

                    // Add horizontal wood grain every few pixels
                    if (gameY % 6 == 0) {
                        color = brownColors[3]; // Dark grain line
                    } else if (gameY % 6 == 1) {
                        color = brownColors[0]; // Light highlight after grain
                    }

                    // Render this pole pixel as a scaled block
                    var screenX:int = poleStartX + (gameX * pixelScale);
                    var screenY:int = poleStartY + (gameY * pixelScale);

                    renderScaledPixel(texture, screenX, screenY, pixelScale, color);
                }
            }

            // Add connection point where pole meets banner
            addPoleConnection(texture, poleStartX, poleStartY, pixelScale);

            trace("BannerActivate: Rendered wooden pole support under right side");

        } catch (error:Error) {
            trace("BannerActivate: Error rendering pole under banner - " + error.message);
        }
    }

    private static function addPoleConnection(texture:BitmapData, poleX:int, poleY:int, pixelScale:int):void {
        try {
            var connectionColor:uint = 0xFF8B7355; // Bronze/brass color for connection
            var shadowColor:uint = 0xFF5D4037; // Dark shadow

            // Add a small connection piece where pole meets banner
            // This represents the mounting hardware
            var connectionWidth:int = pixelScale * 2; // Slightly wider than pole
            var connectionHeight:int = pixelScale; // 1 game pixel tall

            for (var dx:int = 0; dx < connectionWidth; dx++) {
                for (var dy:int = 0; dy < connectionHeight; dy++) {
                    var x:int = poleX + dx;
                    var y:int = poleY - connectionHeight + dy; // Just above where pole starts

                    if (x >= 0 && x < texture.width && y >= 0 && y < texture.height) {
                        texture.setPixel32(x, y, connectionColor);
                    }
                }
            }

            // Add shadow line under connection
            for (var shadowX:int = poleX; shadowX < poleX + connectionWidth; shadowX++) {
                if (shadowX >= 0 && shadowX < texture.width && poleY >= 0 && poleY < texture.height) {
                    texture.setPixel32(shadowX, poleY, shadowColor);
                }
            }

        } catch (error:Error) {
            trace("BannerActivate: Error adding pole connection - " + error.message);
        }
    }

    private static function createFallbackBannerWithPole():BitmapData {
        try {
            var pixelScale:int = 3;
            var bannerWidth:int = 20;
            var bannerHeight:int = 32;
            var poleExtension:int = 16;

            var scaledBannerWidth:int = bannerWidth * pixelScale;
            var scaledBannerHeight:int = bannerHeight * pixelScale;
            var scaledPoleExtension:int = poleExtension * pixelScale;

            var totalWidth:int = scaledBannerWidth;
            var totalHeight:int = scaledBannerHeight + scaledPoleExtension;

            var texture:BitmapData = new BitmapData(totalWidth, totalHeight, true, 0x00000000);

            // Create simple fallback banner pattern
            var colors:Array = [0xFFFF0000, 0xFFFFFFFF, 0xFF0000FF]; // Red, white, blue

            for (var gameY:int = 0; gameY < bannerHeight; gameY++) {
                for (var gameX:int = 0; gameX < bannerWidth; gameX++) {
                    var colorIndex:int = Math.floor(gameY / (bannerHeight / 3)); // Divide into 3 sections
                    var color:uint = colors[Math.min(colorIndex, colors.length - 1)];

                    renderScaledPixel(texture, gameX * pixelScale, gameY * pixelScale, pixelScale, color);
                }
            }

            // Add pole under right side
            renderPoleUnderBanner(texture, bannerWidth, bannerHeight, 2, poleExtension, pixelScale);

            trace("BannerActivate: Created fallback banner with pole support (" + totalWidth + "x" + totalHeight + ")");
            return texture;

        } catch (error:Error) {
            trace("BannerActivate: Error creating fallback banner with pole - " + error.message);
            return new BitmapData(60, 144, false, 0xFF808080); // Scaled gray fallback (20*3 x (32+16)*3)
        }
    }

// Optional: Function to adjust scale factor for different needs



// Optional: Function to adjust scale factor for different needs
    public static function setBannerScale(newScale:int):void {
        if (newScale > 0 && newScale <= 8) {
            // You could store this as a static variable and use it in rendering
            trace("BannerActivate: Banner scale set to " + newScale + "x");
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