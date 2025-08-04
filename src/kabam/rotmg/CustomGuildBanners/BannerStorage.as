package kabam.rotmg.CustomGuildBanners {
import flash.net.SharedObject;
import flash.utils.ByteArray;

public class BannerStorage {

    private static const STORAGE_NAME:String = "rotmgBannerData";
    private static const MAX_SAVED_BANNERS:int = 10; // Limit number of saved banners

    /**
     * Save a banner design to local storage
     * @param bannerData The pixel grid array to save
     * @param slotName Optional name for the save slot (default: "default")
     * @return true if save was successful, false otherwise
     */
    public static function saveBanner(bannerData:Array, slotName:String = "default"):Boolean {
        try {
            var so:SharedObject = SharedObject.getLocal(STORAGE_NAME);

            // Initialize the banners object if it doesn't exist
            if (so.data.banners == null) {
                so.data.banners = {};
            }

            // Validate the banner data before saving
            if (!isValidBannerData(bannerData)) {
                trace("BannerStorage: Invalid banner data, cannot save");
                return false;
            }

            // Save the banner data
            so.data.banners[slotName] = bannerData;

            // Save metadata
            if (so.data.metadata == null) {
                so.data.metadata = {};
            }
            so.data.metadata[slotName] = {
                saveDate: new Date(),
                version: "1.0"
            };

            // Flush to disk
            var flushStatus:String = so.flush();
            if (flushStatus == "flushed") {
                trace("BannerStorage: Banner '" + slotName + "' saved successfully");
                return true;
            } else {
                trace("BannerStorage: Save failed, flush status: " + flushStatus);
                return false;
            }

        } catch (error:Error) {
            trace("BannerStorage: Error saving banner - " + error.message);
            return false;
        }
    }

    /**
     * Load a banner design from local storage
     * @param slotName The name of the save slot to load (default: "default")
     * @return Array containing the banner data, or null if not found
     */
    public static function loadBanner(slotName:String = "default"):Array {
        try {
            var so:SharedObject = SharedObject.getLocal(STORAGE_NAME);

            // Check if the slot exists
            if (so.data.banners == null || so.data.banners[slotName] == null) {
                trace("BannerStorage: No banner found in slot '" + slotName + "'");
                return null;
            }

            var bannerData:Array = so.data.banners[slotName];

            // Validate loaded data
            if (!isValidBannerData(bannerData)) {
                trace("BannerStorage: Loaded banner data is corrupted");
                return null;
            }

            trace("BannerStorage: Banner '" + slotName + "' loaded successfully");
            return bannerData;

        } catch (error:Error) {
            trace("BannerStorage: Error loading banner - " + error.message);
            return null;
        }
    }

    /**
     * Get a list of all saved banner slot names
     * @return Array of strings containing slot names
     */
    public static function getSavedBannersList():Array {
        try {
            var so:SharedObject = SharedObject.getLocal(STORAGE_NAME);
            var bannerList:Array = [];

            if (so.data.banners != null) {
                for (var slotName:String in so.data.banners) {
                    bannerList.push(slotName);
                }
            }

            return bannerList;

        } catch (error:Error) {
            trace("BannerStorage: Error getting banner list - " + error.message);
            return [];
        }
    }

    /**
     * Delete a saved banner
     * @param slotName The name of the slot to delete
     * @return true if deletion was successful, false otherwise
     */
    public static function deleteBanner(slotName:String):Boolean {
        try {
            var so:SharedObject = SharedObject.getLocal(STORAGE_NAME);

            if (so.data.banners != null && so.data.banners[slotName] != null) {
                delete so.data.banners[slotName];

                // Also delete metadata
                if (so.data.metadata != null && so.data.metadata[slotName] != null) {
                    delete so.data.metadata[slotName];
                }

                so.flush();
                trace("BannerStorage: Banner '" + slotName + "' deleted successfully");
                return true;
            } else {
                trace("BannerStorage: Banner '" + slotName + "' not found, cannot delete");
                return false;
            }

        } catch (error:Error) {
            trace("BannerStorage: Error deleting banner - " + error.message);
            return false;
        }
    }

    /**
     * Clear all saved banners
     * @return true if successful, false otherwise
     */
    public static function clearAllBanners():Boolean {
        try {
            var so:SharedObject = SharedObject.getLocal(STORAGE_NAME);
            so.clear();
            so.flush();
            trace("BannerStorage: All banners cleared");
            return true;

        } catch (error:Error) {
            trace("BannerStorage: Error clearing banners - " + error.message);
            return false;
        }
    }

    /**
     * Get metadata for a saved banner
     * @param slotName The slot name to get metadata for
     * @return Object containing metadata, or null if not found
     */
    public static function getBannerMetadata(slotName:String):Object {
        try {
            var so:SharedObject = SharedObject.getLocal(STORAGE_NAME);

            if (so.data.metadata != null && so.data.metadata[slotName] != null) {
                return so.data.metadata[slotName];
            }

            return null;

        } catch (error:Error) {
            trace("BannerStorage: Error getting metadata - " + error.message);
            return null;
        }
    }

    /**
     * Validate banner data structure
     * @param bannerData The data to validate
     * @return true if valid, false otherwise
     */
    private static function isValidBannerData(bannerData:Array):Boolean {
        if (bannerData == null) {
            return false;
        }

        // Check if it's a 2D array with correct dimensions
        if (bannerData.length != 32) { // 32 rows
            return false;
        }

        for (var row:int = 0; row < bannerData.length; row++) {
            if (bannerData[row] == null || bannerData[row].length != 20) { // 20 columns
                return false;
            }

            // Check if each pixel value is a valid uint or 0
            for (var col:int = 0; col < bannerData[row].length; col++) {
                var pixelValue:* = bannerData[row][col];
                if (!(pixelValue is Number) || pixelValue < 0 || pixelValue > 0xFFFFFF) {
                    return false;
                }
            }
        }

        return true;
    }

    /**
     * Get storage usage information
     * @return Object with storage statistics
     */
    public static function getStorageInfo():Object {
        try {
            var so:SharedObject = SharedObject.getLocal(STORAGE_NAME);
            var bannerCount:int = 0;

            if (so.data.banners != null) {
                for (var slotName:String in so.data.banners) {
                    bannerCount++;
                }
            }

            return {
                totalBanners: bannerCount,
                maxBanners: MAX_SAVED_BANNERS,
                storageSize: so.size
            };

        } catch (error:Error) {
            trace("BannerStorage: Error getting storage info - " + error.message);
            return {
                totalBanners: 0,
                maxBanners: MAX_SAVED_BANNERS,
                storageSize: 0
            };
        }
    }
}
}