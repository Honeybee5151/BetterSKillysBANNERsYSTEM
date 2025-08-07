package kabam.rotmg.CustomGuildBanners {
import kabam.rotmg.messaging.impl.GameServerConnection;
import flash.utils.Timer;
import flash.events.TimerEvent;

/**
 * Handles guild hall banner application - separate from regular banner activation
 * Uses BannerActivate's rendering logic but manages guild hall specific detection
 */
public class GuildHallBannerSystem {

    // Banner object type from your XML
    private static const BANNER_OBJECT_TYPE:int = 0x3787;

    /**
     * Main entry point - call when entering a guildhall
     * @param guildId The guild ID of the guildhall being entered
     */
    public static function applyGuildHallBanners(guildId:int):void {
        try {
            trace("GuildHallBannerSystem: Applying guild " + guildId + " banners to guildhall");

            // Check if we have banner data for this guild
            if (!BulkBannerSystem.hasBanner(guildId)) {
                trace("GuildHallBannerSystem: No banner data for guild " + guildId + ", using default");
                return;
            }

            // Find all banner entities in the current map
            var bannerEntities:Array = findBannerEntitiesInCurrentMap();

            trace("GuildHallBannerSystem: Found " + bannerEntities.length + " banner entities in guildhall");

            // Apply the guild's banner to each banner entity
            for each (var bannerEntity:* in bannerEntities) {
                applyGuildBannerToEntity(bannerEntity, guildId);
            }

        } catch (error:Error) {
            trace("GuildHallBannerSystem: Error applying guildhall banners - " + error.message);
        }
    }

    /**
     * Find all banner entities in the current map
     */
    private static function findBannerEntitiesInCurrentMap():Array {
        var bannerEntities:Array = [];

        try {
            var gameScreen:* = GameServerConnection.instance.gs_;
            if (!gameScreen || !gameScreen.map || !gameScreen.map.goDict_) {
                return bannerEntities;
            }

            // Iterate through all entities in the map
            for each (var entity:* in gameScreen.map.goDict_) {
                if (isBannerEntity(entity)) {
                    bannerEntities.push(entity);
                }
            }

        } catch (error:Error) {
            trace("GuildHallBannerSystem: Error finding banner entities - " + error.message);
        }

        return bannerEntities;
    }

    /**
     * Check if an entity is a banner (customize this for your banner detection)
     */
    private static function isBannerEntity(entity:*):Boolean {
        try {
            // Method 1: Check by object type/ID
            if (entity.hasOwnProperty("objectType_")) {
                var objectType:int = entity.objectType_;
                if (objectType == BANNER_OBJECT_TYPE) {
                    return true;
                }
            }

            // Method 2: Check by class name
            var entityClass:String = entity.constructor.toString();
            if (entityClass.indexOf("Banner") !== -1 || entityClass.indexOf("GuildBanner") !== -1) {
                return true;
            }

            // Method 3: Check by custom property
            if (entity.hasOwnProperty("isBannerEntity") && entity.isBannerEntity) {
                return true;
            }

        } catch (error:Error) {
            // Ignore errors in detection
        }

        return false;
    }

    /**
     * Apply guild banner design to a specific entity using BannerActivate's rendering
     */
    private static function applyGuildBannerToEntity(bannerEntity:*, guildId:int):void {
        try {
            trace("GuildHallBannerSystem: Applying guild " + guildId + " banner to entity " + bannerEntity.objectId_);

            var hexData:String = BulkBannerSystem.getHexData(guildId);

            if (hexData && hexData.length > 100) {
                // Use BannerActivate's existing rendering method
                var guildTexture:* = BannerActivate.renderBannerFromHexString(hexData);

                if (guildTexture) {
                    // Apply to entity
                    bannerEntity.customBannerTexture_ = guildTexture;
                    bannerEntity.hasCustomBanner_ = true;
                    bannerEntity.guildId_ = guildId;
                    bannerEntity.isGuildHallBanner_ = true; // Mark as guildhall banner

                    // Force refresh using BannerActivate's method
                    BannerActivate.forceEntityRefresh(bannerEntity);

                    trace("GuildHallBannerSystem: Successfully applied guild banner to entity " + bannerEntity.objectId_);
                } else {
                    trace("GuildHallBannerSystem: Failed to render banner for guild " + guildId);
                }
            } else {
                trace("GuildHallBannerSystem: Invalid hex data for guild " + guildId);
            }

        } catch (error:Error) {
            trace("GuildHallBannerSystem: Error applying guild banner to entity - " + error.message);
        }
    }

    /**
     * Call this method when entering a new map/room
     * Add this to your map loading or room transition code
     */
    public static function onMapEntered(mapId:String, currentPlayer:* = null):void {
        try {
            // Method 1: Try to extract guild ID from map name
            var guildId:int = extractGuildIdFromMapId(mapId);

            if (guildId > 0) {
                trace("GuildHallBannerSystem: Entered guildhall for guild " + guildId + " (from map name)");

                // Small delay to ensure all entities are loaded

                    applyGuildHallBanners(guildId);

                return;
            }

            // Method 2: If map detection fails, use player's guild (more reliable)
            if (currentPlayer && currentPlayer.hasOwnProperty("guildId_") && currentPlayer.guildId_ > 0) {
                trace("GuildHallBannerSystem: Using player's guild " + currentPlayer.guildId_ + " for banners");


                    applyGuildHallBanners(currentPlayer.guildId_);

            }

        } catch (error:Error) {
            trace("GuildHallBannerSystem: Error on map entered - " + error.message);
        }
    }

    /**
     * Extract guild ID from map identifier
     * Customize this to match your actual guildhall naming convention
     */
    private static function extractGuildIdFromMapId(mapId:String):int {
        try {
            trace("GuildHallBannerSystem: Trying to extract guild ID from: '" + mapId + "'");

            // YOUR ACTUAL PATTERN: "Guild Hall 1", "Guild Hall 2", etc.
            if (mapId.indexOf("Guild Hall ") === 0) {
                var idStr:String = mapId.replace("Guild Hall ", "");
                var guildId:int = parseInt(idStr);
                trace("GuildHallBannerSystem: Extracted guild ID: " + guildId);
                return guildId;
            }

            // Backup patterns in case format changes
            if (mapId.indexOf("GuildHall") === 0) {
                var idStr2:String = mapId.replace("GuildHall", "");
                return parseInt(idStr2);
            }

            if (mapId.indexOf("guild_") === 0) {
                var idStr3:String = mapId.replace("guild_", "");
                return parseInt(idStr3);
            }

            trace("GuildHallBannerSystem: No guild hall pattern matched for: " + mapId);

        } catch (error:Error) {
            trace("GuildHallBannerSystem: Error extracting guild ID from map " + mapId + " - " + error.message);
        }

        return 0; // Not a guildhall
    }

    /**
     * Alternative: Apply banners based on current player's guild
     * Use this if you can't determine guild from map ID
     */
    public static function applyCurrentPlayerGuildBanners(player:*):void {
        try {
            if (!player || !player.hasOwnProperty("guildId_")) {
                trace("GuildHallBannerSystem: Player has no guild");
                return;
            }

            var playerGuildId:int = player.guildId_;
            if (playerGuildId > 0) {
                trace("GuildHallBannerSystem: Applying player's guild " + playerGuildId + " banners");
                applyGuildHallBanners(playerGuildId);
            }

        } catch (error:Error) {
            trace("GuildHallBannerSystem: Error applying current player guild banners - " + error.message);
        }
    }

    /**
     * Check if currently in a guildhall
     */
    public static function isInGuildHall():Boolean {
        try {
            var gameScreen:* = GameServerConnection.instance.gs_;
            if (gameScreen && gameScreen.map && gameScreen.map.mapId_) {
                var mapId:String = gameScreen.map.mapId_;
                return extractGuildIdFromMapId(mapId) > 0;
            }
        } catch (error:Error) {
            // Ignore errors
        }
        return false;
    }

    /**
     * Get the guild ID of the current guildhall (0 if not in guildhall)
     */
    public static function getCurrentGuildHallId():int {
        try {
            var gameScreen:* = GameServerConnection.instance.gs_;
            if (gameScreen && gameScreen.map && gameScreen.map.mapId_) {
                var mapId:String = gameScreen.map.mapId_;
                return extractGuildIdFromMapId(mapId);
            }
        } catch (error:Error) {
            // Ignore errors
        }
        return 0;
    }

    /**
     * Refresh all banners in current guildhall
     * Call this if guild banner data is updated while in guildhall
     */
    public static function refreshGuildHallBanners():void {
        var currentGuildId:int = getCurrentGuildHallId();
        if (currentGuildId > 0) {
            trace("GuildHallBannerSystem: Refreshing banners for guild " + currentGuildId);
            applyGuildHallBanners(currentGuildId);
        }
    }

    /**
     * Helper timeout function
     */
    private static function setTimeout(callback:Function, delay:int):void {
        var timer:Timer = new Timer(delay, 1);
        timer.addEventListener(TimerEvent.TIMER_COMPLETE, function(e:TimerEvent):void {
            callback();
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE, arguments.callee);
        });
        timer.start();
    }

    /**
     * Debug method to test guild hall banner system
     */
    public static function debugGuildHallSystem():void {
        trace("=== GuildHall Banner System Debug ===");
        trace("In Guild Hall: " + isInGuildHall());
        trace("Guild Hall ID: " + getCurrentGuildHallId());

        var bannerCount:int = findBannerEntitiesInCurrentMap().length;
        trace("Banner Entities Found: " + bannerCount);

        if (bannerCount > 0) {
            trace("Testing banner application...");
            var testGuildId:int = getCurrentGuildHallId();
            if (testGuildId > 0) {
                applyGuildHallBanners(testGuildId);
            }
        }
    }
}
}