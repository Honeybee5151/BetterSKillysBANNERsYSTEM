package kabam.rotmg.CustomGuildBanners {
import com.company.assembleegameclient.objects.Player;

import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.utils.Dictionary;

import kabam.rotmg.appengine.api.AppEngineClient;
import kabam.rotmg.account.core.Account;
import kabam.rotmg.core.StaticInjectorContext;
import kabam.rotmg.messaging.impl.GameServerConnection;

/**
 * Integrated banner activation system that works with entity system
 * Handles both HTTP requests (legacy) and entity mapping (new approach)
 */
public class BannerActivate {

    // Track placed banners by instance ID
    private static var _placedBanners:Dictionary = new Dictionary();

    // NEW: Map entity IDs to banner appearance data
    private static var _bannerInstanceMap:Dictionary = new Dictionary();

    private static var _instance:BannerActivate;

    private static var _pendingBanners:Array = [];

    public function BannerActivate() {
        _instance = this;
        trace("BannerActivate: Integrated system initialized");
    }

    public static function getInstance():BannerActivate {
        if (!_instance) {
            _instance = new BannerActivate();

        }
        return _instance;
    }

    // ====== ITEM ACTIVATION (when player uses banner item) ======

    /**
     * Called when banner item is used - STILL SENDS HTTP REQUEST FOR NOW
     */
    public function activate(player:Player, item:*):Boolean {
        try {
            trace("BannerActivate: Player " + player.name_ + " using banner item");

            // Get player's guild ID
            var guildId:int = getPlayerGuildId(player);
            if (guildId <= 0) {
                showMessage(player, "You must be in a guild to place banners!");
                return false;
            }

            // Check if we have the guild's banner data using BulkBannerSystem
            if (!BulkBannerSystem.hasBanner(guildId)) {
                showMessage(player, "Guild banner data not available! Please wait for sync to complete.");
                return false;
            }

            // Basic validation
            if (!canPlaceBanner(player)) {
                return false;
            }

            // The C# server will handle the actual entity creation
            // and send us a BANNER_ACTIVATE notification
            showMessage(player, "Placing guild banner...");
            return true; // Item will be consumed, server handles the rest

        } catch (error:Error) {
            trace("BannerActivate: Error - " + error.message);
            return false;
        }
    }

    // ====== NEW: ENTITY MAPPING SYSTEM ======

    /**
     * Called when server sends BANNER_ACTIVATE notification
     * Maps entity ID to guild appearance data and DIRECTLY modifies the entity
     */
    public static function mapEntityToBanner(entityId:int, guildId:int, instanceId:String):void {
        try {
            trace("BannerActivate: Mapping entity " + entityId + " to guild " + guildId + " banner");

            var bannerData:Object = {
                entityId: entityId,
                guildId: guildId,
                instanceId: instanceId,
                timestamp: new Date().time
            };

            // Store mapping: entity ID -> guild appearance
            _bannerInstanceMap[entityId.toString()] = bannerData;

            // DIRECTLY MODIFY THE ENTITY'S APPEARANCE RIGHT NOW
            applyGuildBannerToEntity(entityId, guildId);

            trace("BannerActivate: Entity " + entityId + " mapped to guild " + guildId + " banner and appearance applied");

        } catch (error:Error) {
            trace("BannerActivate: Error mapping entity to banner - " + error.message);
        }
    }

    /**
     * Directly apply guild banner appearance to an existing entity
     */
    public static function applyGuildBannerToEntity(entityId:int, guildId:int):void {
        trace("!!! applyGuildBannerToEntity CALLED with entityId=" + entityId + " guildId=" + guildId);
            var gameEntity:* = findEntityInWorld(entityId);
            if (!gameEntity) {
                trace("Entity not found, queuing for later: " + entityId);
                _pendingBanners.push({entityId: entityId, guildId: guildId});
                return;
            }
        try {
            trace("BannerActivate: Applying guild " + guildId + " banner to entity " + entityId);

            // Get guild banner hex data
            var guildHexData:String = BulkBannerSystem.getHexData(guildId);
            if (!guildHexData) {
                trace("BannerActivate: No hex data for guild " + guildId + ", using default");
                guildHexData = getDefaultBannerHex();
            }

            // Find the entity in the game world (you'll need to adapt this to your game's entity system)

            // Get the entity's current bitmap/texture
            var entityBitmap:Bitmap = getEntityBitmap(gameEntity);
            if (!entityBitmap || !entityBitmap.bitmapData) {
                trace("BannerActivate: Could not get bitmap for entity " + entityId);
                return;
            }

            // Apply guild colors directly to the entity's bitmap using setPixel
            applyGuildColorsWithSetPixel(entityBitmap.bitmapData, guildHexData);

            trace("BannerActivate: Successfully applied guild colors to entity " + entityId);

        } catch (error:Error) {
            trace("BannerActivate: Error applying banner to entity - " + error.message);
        }
    }

    /**
     * Find entity in the game world
     */
    private static function findEntityInWorld(entityId:int):* {
        var keys:Array = [];
        for (var k:* in GameServerConnection.instance.gs_.map.goDict_) {
            keys.push(k);
        }
        trace("Keys in goDict_: " + keys.join(", "));
        try {
            return GameServerConnection.instance.gs_.map.goDict_[entityId];

        } catch (error:Error) {
            trace("BannerActivate: Error finding entity in world - " + error.message);
            return null;
        }
    }

    /**
     * Get entity's bitmap for pixel modification - TESTING RUNTIME
     */
    private static function getEntityBitmap(gameEntity:*):Bitmap {
        try {
            trace("BannerActivate: Testing entity bitmap access for entity: " + gameEntity);

            // Test each possibility and see which ones work
            try {
                if (gameEntity.bitmap_) {
                    trace("BannerActivate: SUCCESS - gameEntity.bitmap_ exists: " + gameEntity.bitmap_);
                    return gameEntity.bitmap_;
                }
            } catch (e:Error) { trace("BannerActivate: gameEntity.bitmap_ failed: " + e.message); }

            try {
                if (gameEntity.bitmapData_) {
                    trace("BannerActivate: SUCCESS - gameEntity.bitmapData_ exists: " + gameEntity.bitmapData_);
                    // If it's BitmapData, create a Bitmap from it
                    return new Bitmap(gameEntity.bitmapData_);
                }
            } catch (e:Error) { trace("BannerActivate: gameEntity.bitmapData_ failed: " + e.message); }

            try {
                if (gameEntity.texture_) {
                    trace("BannerActivate: SUCCESS - gameEntity.texture_ exists: " + gameEntity.texture_);
                    return gameEntity.texture_;
                }
            } catch (e:Error) { trace("BannerActivate: gameEntity.texture_ failed: " + e.message); }

            try {
                if (gameEntity.sprite_) {
                    trace("BannerActivate: SUCCESS - gameEntity.sprite_ exists: " + gameEntity.sprite_);
                    return gameEntity.sprite_;
                }
            } catch (e:Error) { trace("BannerActivate: gameEntity.sprite_ failed: " + e.message); }

            try {
                var bitmap = gameEntity.getBitmap();
                if (bitmap) {
                    trace("BannerActivate: SUCCESS - gameEntity.getBitmap() returned: " + bitmap);
                    return bitmap;
                }
            } catch (e:Error) { trace("BannerActivate: gameEntity.getBitmap() failed: " + e.message); }

            try {
                var texture = gameEntity.getTexture();
                if (texture) {
                    trace("BannerActivate: SUCCESS - gameEntity.getTexture() returned: " + texture);
                    return texture;
                }
            } catch (e:Error) { trace("BannerActivate: gameEntity.getTexture() failed: " + e.message); }

            trace("BannerActivate: No bitmap access method worked for entity");
            return null;

        } catch (error:Error) {
            trace("BannerActivate: Error getting entity bitmap - " + error.message);
            return null;
        }
    }

    /**
     * Called by entity rendering system to get banner appearance
     * Returns banner shape for specific entity ID
     */
    public static function getBannerForEntity(entityId:int):* {
        try {
            var entityKey:String = entityId.toString();
            if (_bannerInstanceMap[entityKey]) {
                var bannerData:Object = _bannerInstanceMap[entityKey];
                var guildId:int = bannerData.guildId;

                trace("BannerActivate: Entity " + entityId + " should render as guild " + guildId + " banner");

                // Use BannerRetrievalSystem to get the actual guild banner
                BannerRetrievalSystem.requestGuildBanner(guildId, function (bannerShape:*, receivedGuildId:int):void {
                    if (bannerShape) {
                        trace("BannerActivate: Retrieved banner shape for entity " + entityId);
                        // The entity system will handle positioning
                    } else {
                        trace("BannerActivate: Failed to retrieve banner for guild " + guildId);
                    }
                }, 16);

                return null; // Async - banner will be available after retrieval
            }

            return null; // This entity is not a banner

        } catch (error:Error) {
            trace("BannerActivate: Error getting banner for entity - " + error.message);
            return null;
        }
    }

    /**
     * Remove entity mapping when banner is removed
     */
    public static function removeEntityMapping(entityId:int):void {
        try {
            var entityKey:String = entityId.toString();
            if (_bannerInstanceMap[entityKey]) {
                var bannerData:Object = _bannerInstanceMap[entityKey];
                trace("BannerActivate: Removing entity " + entityId + " banner mapping");
                delete _bannerInstanceMap[entityKey];
            }
        } catch (error:Error) {
            trace("BannerActivate: Error removing entity mapping - " + error.message);
        }
    }

    // ====== LEGACY: BITMAP RENDERING (for compatibility) ======

    /**
     * Handle server response - LEGACY METHOD
     * Call this when you receive a banner placement packet from server
     */
    public static function handleBannerPlacedFromServer(bannerInstanceId:String, worldX:Number, worldY:Number,
                                                        guildId:int, objectId:int):void {
        try {
            trace("BannerActivate: LEGACY - Rendering banner " + bannerInstanceId + " for guild " + guildId);

            // Get guild banner hex data from BulkBannerSystem
            var guildHexData:String = BulkBannerSystem.getHexData(guildId);
            if (!guildHexData) {
                trace("BannerActivate: No hex data for guild " + guildId + ", using default");
                guildHexData = getDefaultBannerHex();
            }

            // Create banner with guild colors applied
            var bannerBitmap:Bitmap = createBannerWithSetPixel(guildHexData, objectId);

            if (bannerBitmap) {
                // Position the banner
                bannerBitmap.x = worldX;
                bannerBitmap.y = worldY;

                // Add to world (you'll need to adapt this to your world system)
                addBitmapToWorld(bannerBitmap);

                // Track it
                _placedBanners[bannerInstanceId] = bannerBitmap;

                trace("BannerActivate: Successfully rendered banner " + bannerInstanceId);
            }

        } catch (error:Error) {
            trace("BannerActivate: Error rendering banner - " + error.message);
        }
    }

    /**
     * Create banner bitmap with guild colors using setPixel
     */
    private static function createBannerWithSetPixel(guildHexData:String, objectId:int):Bitmap {
        try {
            // Create base banner bitmap (64x64 as example)
            var baseBitmapData:BitmapData = new BitmapData(64, 64, true, 0x00000000);

            // Create simple banner base
            createBaseBannerTexture(baseBitmapData);

            // Apply guild colors using setPixel
            applyGuildColorsWithSetPixel(baseBitmapData, guildHexData);

            // Create bitmap from the modified data
            var customBitmap:Bitmap = new Bitmap(baseBitmapData);

            return customBitmap;

        } catch (error:Error) {
            trace("BannerActivate: Error creating banner bitmap - " + error.message);
            return null;
        }
    }

    /**
     * Apply guild colors to bitmap using setPixel
     */
    private static function applyGuildColorsWithSetPixel(bitmapData:BitmapData, guildHexData:String):void {
        try {
            trace("BannerActivate: Applying guild colors using setPixel");

            // Parse hex data into color array
            var colorPixels:Array = parseHexDataToColors(guildHexData);
            if (!colorPixels) {
                trace("BannerActivate: Failed to parse hex data");
                return;
            }

            // Define banner customizable area
            var bannerStartX:int = 44;
            var bannerStartY:int = 16;
            var bannerWidth:int = 20;
            var bannerHeight:int = 32;

            // Apply pixels using setPixel
            for (var row:int = 0; row < bannerHeight && row < colorPixels.length; row++) {
                var rowColors:Array = colorPixels[row];
                if (rowColors) {
                    for (var col:int = 0; col < bannerWidth && col < rowColors.length; col++) {
                        var pixelColor:uint = rowColors[col];

                        // Only set non-transparent pixels
                        if (pixelColor > 0) {
                            var bitmapX:int = bannerStartX + col;
                            var bitmapY:int = bannerStartY + row;

                            // Ensure within bitmap bounds
                            if (bitmapX < bitmapData.width && bitmapY < bitmapData.height) {
                                bitmapData.setPixel32(bitmapX, bitmapY, pixelColor);
                            }
                        }
                    }
                }
            }

            trace("BannerActivate: Successfully applied guild colors");

        } catch (error:Error) {
            trace("BannerActivate: Error applying colors - " + error.message);
        }
    }

    // ====== HELPER METHODS ======

    private function getPlayerGuildId(player:Player):int {
        // TODO: Get from your guild system
        return 1; // Placeholder
    }

    private function canPlaceBanner(player:Player):Boolean {
        // TODO: Add validation
        return true;
    }

    private function showMessage(player:Player, message:String):void {
        trace("Message to " + player.name_ + ": " + message);
        // TODO: Show actual message to player
    }

    private static function createBaseBannerTexture(bitmapData:BitmapData):void {
        // Create a simple banner base
        for (var x:int = 0; x < bitmapData.width; x++) {
            for (var y:int = 0; y < bitmapData.height; y++) {
                // Create a simple banner pole and base
                if (x >= 0 && x <= 4) {
                    bitmapData.setPixel32(x, y, 0xFF8B4513); // Brown pole
                } else if (x >= 5 && x <= 60 && y >= 5 && y <= 50) {
                    bitmapData.setPixel32(x, y, 0xFFFFFFFF); // White banner area
                }
            }
        }
    }

    private static function parseHexDataToColors(hexData:String):Array {
        try {
            var rows:Array = hexData.split("|");
            var colorArray:Array = [];

            for (var i:int = 0; i < rows.length; i++) {
                var rowString:String = rows[i];
                var rowColors:Array = [];

                if (rowString) {
                    var colorStrings:Array = rowString.split(",");
                    for (var j:int = 0; j < colorStrings.length; j++) {
                        var colorHex:String = colorStrings[j];
                        if (colorHex && colorHex.length >= 6) {
                            var color:uint = parseInt("0xFF" + colorHex, 16);
                            rowColors.push(color);
                        } else {
                            rowColors.push(0x00000000); // Transparent
                        }
                    }
                }
                colorArray.push(rowColors);
            }

            return colorArray;

        } catch (error:Error) {
            trace("BannerActivate: Error parsing hex data - " + error.message);
            return null;
        }
    }

    private static function getDefaultBannerHex():String {
        return "FFFFFF,FFFFFF,FFFFFF|FFFFFF,FFFFFF,FFFFFF|FFFFFF,FFFFFF,FFFFFF";
    }

    private static function addBitmapToWorld(bitmap:Bitmap):void {
        try {
            // TODO: Add bitmap to your world/stage system
            trace("BannerActivate: Added banner bitmap to world");

        } catch (error:Error) {
            trace("BannerActivate: Error adding bitmap to world - " + error.message);
        }
    }

    private static function getAuthenticationData():Object {
        try {
            var account:Account = StaticInjectorContext.getInjector().getInstance(Account);
            if (account) {
                return {
                    guid: account.getUserId(),
                    password: account.getPassword()
                };
            }
        } catch (error:Error) {
            trace("BannerActivate: Error getting auth data - " + error.message);
        }

        return {
            guid: "",
            password: ""
        };
    }

    // Alternative method name for activation systems that use "create"
    public function create(player:Player, item:*):Boolean {
        return activate(player, item);
    }

    /**
     * Get system status
     */
    public static function getStatus():Object {
        var entityMappings:int = 0;
        for (var entityId:String in _bannerInstanceMap) {
            entityMappings++;
        }

        return {
            entityMappings: entityMappings,
            legacyBanners: getLegacyBannerCount(),
            systemReady: _instance != null
        };
    }

    private static function getLegacyBannerCount():int {
        var count:int = 0;
        for (var bannerId:String in _placedBanners) {
            count++;
        }
        return count;
    }
}
}