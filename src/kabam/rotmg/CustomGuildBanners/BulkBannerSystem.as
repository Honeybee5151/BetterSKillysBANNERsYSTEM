package kabam.rotmg.CustomGuildBanners {
import flash.display.Shape;

import kabam.rotmg.appengine.api.AppEngineClient;
import kabam.rotmg.core.StaticInjectorContext;
import kabam.rotmg.account.core.Account;

import flash.display.Bitmap;
import flash.events.Event;
import flash.filesystem.File;
import flash.filesystem.FileStream;
import flash.filesystem.FileMode;

public class BulkBannerSystem {

    private static var _bannerManifest:Object = {}; // guildId -> {version, lastUpdate}
    private static var _downloadQueue:Array = [];
    private static var _downloading:Boolean = false;
    private static var _loginCallback:Function = null;

    private static var _cacheDirectory:File;
    private static const CACHE_FOLDER:String = "guildBanners";
    private static const MANIFEST_FILE:String = "bannerManifest.json";
    // Add this line after your other static variables
    private static var _hexCache:Object = {};

    /**
     * Call this at login to sync all banners
     */
    public static function syncBannersAtLogin(callback:Function = null):void {
        trace("BulkBannerSystem: Starting banner sync at login");
        _loginCallback = callback;

        initCacheDirectory();
        loadLocalManifest();
        requestBannerManifestFromServer();
    }

    /**
     * Initialize cache directory
     */
    private static function initCacheDirectory():void {
        if (!_cacheDirectory) {
            _cacheDirectory = File.applicationStorageDirectory.resolvePath(CACHE_FOLDER);
            if (!_cacheDirectory.exists) {
                _cacheDirectory.createDirectory();
                trace("BulkBannerSystem: Created cache directory");
            }
        }
    }

    /**
     * Load local manifest to see what we already have
     */
    private static function loadLocalManifest():void {
        var manifestFile:File = _cacheDirectory.resolvePath(MANIFEST_FILE);

        if (manifestFile.exists) {
            try {
                var fileStream:FileStream = new FileStream();
                fileStream.open(manifestFile, FileMode.READ);
                var manifestData:String = fileStream.readUTFBytes(fileStream.bytesAvailable);
                fileStream.close();

                _bannerManifest = JSON.parse(manifestData);
                trace("BulkBannerSystem: Loaded local manifest with " +
                        getObjectKeyCount(_bannerManifest) + " banners");

            } catch (error:Error) {
                trace("BulkBannerSystem: Error loading manifest - " + error.message);
                _bannerManifest = {};
            }
        } else {
            trace("BulkBannerSystem: No local manifest found");
            _bannerManifest = {};
        }
    }

    /**
     * Save manifest to file
     */
    private static function saveLocalManifest():void {
        var manifestFile:File = _cacheDirectory.resolvePath(MANIFEST_FILE);

        try {
            var fileStream:FileStream = new FileStream();
            fileStream.open(manifestFile, FileMode.WRITE);
            fileStream.writeUTFBytes(JSON.stringify(_bannerManifest));
            fileStream.close();

            trace("BulkBannerSystem: Saved manifest");

        } catch (error:Error) {
            trace("BulkBannerSystem: Error saving manifest - " + error.message);
        }
    }

    /**
     * Request banner manifest from server to see what's new/updated
     */
    private static function requestBannerManifestFromServer():void {
        trace("BulkBannerSystem: Requesting banner manifest from server");

        var authData:Object = getAuthenticationData();
        var requestData:Object = {
            guid: authData.guid,
            password: authData.password,
            action: "getBannerManifest",
            currentManifest: _bannerManifest // Send what we have
        };

        try {
            var client:AppEngineClient = StaticInjectorContext.getInjector().getInstance(AppEngineClient);

            client.complete.addOnce(function (success:Boolean, data:String):void {
                handleManifestResponse(success, data);
            });

            client.sendRequest("/guild/getBannerManifest", requestData);

        } catch (error:Error) {
            trace("BulkBannerSystem: Error requesting manifest - " + error.message);
            finishLoginSync(false);
        }
    }

    /**
     * Handle server manifest response
     */
    private static function handleManifestResponse(success:Boolean, data:String):void {
        if (!success || !data) {
            trace("BulkBannerSystem: Failed to get manifest from server");
            finishLoginSync(false);
            return;
        }

        try {
            var response:Object = JSON.parse(data);

            if (!response.success) {
                trace("BulkBannerSystem: Server returned error: " + (response.message || "Unknown"));
                finishLoginSync(false);
                return;
            }

            var updatedBanners:Array = response.updatedBanners || [];
            var deletedBanners:Array = response.deletedBanners || [];

            trace("BulkBannerSystem: Server says " + updatedBanners.length +
                    " banners need updating, " + deletedBanners.length + " need deleting");

            // Handle deletions first
            handleBannerDeletions(deletedBanners);

            // Queue downloads for updated banners
            if (updatedBanners.length > 0) {
                queueBannerDownloads(updatedBanners);
                startBannerDownloads();
            } else {
                finishLoginSync(true);
            }

        } catch (error:Error) {
            trace("BulkBannerSystem: Error parsing manifest response - " + error.message);
            finishLoginSync(false);
        }
    }

    /**
     * Handle banner deletions
     */
    private static function handleBannerDeletions(deletedBanners:Array):void {
        for each (var guildId:int in deletedBanners) {
            // Delete local file
            var bannerFile:File = _cacheDirectory.resolvePath(guildId + ".banner");
            if (bannerFile.exists) {
                try {
                    bannerFile.deleteFile();
                    trace("BulkBannerSystem: Deleted banner for guild " + guildId);
                } catch (error:Error) {
                    trace("BulkBannerSystem: Error deleting banner " + guildId + " - " + error.message);
                }
            }

            // Remove from manifest
            delete _bannerManifest[guildId];
        }

        if (deletedBanners.length > 0) {
            saveLocalManifest();
        }
    }

    /**
     * Queue banner downloads
     */
    private static function queueBannerDownloads(updatedBanners:Array):void {
        _downloadQueue = [];

        for each (var bannerInfo:Object in updatedBanners) {
            _downloadQueue.push({
                guildId: bannerInfo.guildId,
                version: bannerInfo.version,
                lastUpdate: bannerInfo.lastUpdate
            });
        }

        trace("BulkBannerSystem: Queued " + _downloadQueue.length + " banner downloads");
    }

    /**
     * Start downloading banners one by one
     */
    private static function startBannerDownloads():void {
        if (_downloading || _downloadQueue.length == 0) {
            return;
        }

        _downloading = true;
        downloadNextBanner();
    }

    /**
     * Download the next banner in queue
     */
    private static function downloadNextBanner():void {
        trace("DOWNLOAD ATTEMPT: Guild " + guildId);
        if (_downloadQueue.length == 0) {
            _downloading = false;
            finishLoginSync(true);
            return;
        }

        var bannerInfo:Object = _downloadQueue.shift();
        var guildId:int = bannerInfo.guildId;

        trace("BulkBannerSystem: Downloading banner for guild " + guildId +
                " (" + (_downloadQueue.length + 1) + " remaining)");


        var authData:Object = getAuthenticationData();
        var requestData:Object = {
            guid: authData.guid,
            password: authData.password,
            guildId: guildId
        };

        try {
            var client:AppEngineClient = StaticInjectorContext.getInjector().getInstance(AppEngineClient);

            client.complete.addOnce(function (success:Boolean, data:String):void {
                handleBannerDownload(success, data, bannerInfo);
            });

            client.sendRequest("/guild/getGuildBanner", requestData);

        } catch (error:Error) {
            trace("BulkBannerSystem: Error downloading banner " + guildId + " - " + error.message);
            downloadNextBanner(); // Continue with next
        }
    }

    /**
     * Handle individual banner download
     */
    private static function handleBannerDownload(success:Boolean, data:String, bannerInfo:Object):void {
        var guildId:int = bannerInfo.guildId;
        trace("DOWNLOAD RESULT: " + success + " for guild " + guildId);

        if (!success || !data) {
            trace("BulkBannerSystem: Failed to download banner for guild " + guildId);
            downloadNextBanner();
            return;
        }

        try {
            var response:Object = JSON.parse(data);

            if (response.success && response.bannerData) {
                // Save banner to file
                var bannerFile:File = _cacheDirectory.resolvePath(guildId + ".banner");
                var fileStream:FileStream = new FileStream();
                fileStream.open(bannerFile, FileMode.WRITE);
                fileStream.writeUTFBytes(response.bannerData);
                fileStream.close();

                // Update manifest
                _bannerManifest[guildId] = {
                    version: bannerInfo.version,
                    lastUpdate: bannerInfo.lastUpdate
                };

                trace("BulkBannerSystem: Saved banner for guild " + guildId);
                _hexCache[guildId] = response.bannerData;
            } else {
                trace("BulkBannerSystem: Server error for guild " + guildId + ": " +
                        (response.message || "Unknown error"));
            }

        } catch (error:Error) {
            trace("BulkBannerSystem: Error processing banner " + guildId + " - " + error.message);
        }

        // Continue with next download
        downloadNextBanner();
    }

    /**
     * Finish login sync process
     */
    private static function finishLoginSync(success:Boolean):void {
        if (success) {
            saveLocalManifest();
            trace("BulkBannerSystem: Banner sync completed successfully");
        } else {
            trace("BulkBannerSystem: Banner sync failed");
        }

        if (_loginCallback != null) {
            try {
                _loginCallback(success);
            } catch (error:Error) {
                trace("BulkBannerSystem: Error in login callback - " + error.message);
            }
            _loginCallback = null;
        }
    }

    /**
     * Get a banner (instant - from local files only)
     */
    /*

    /**
     * Check if banner exists locally
     */
    public static function hasBanner(guildId:int):Boolean {
        initCacheDirectory();
        var bannerFile:File = _cacheDirectory.resolvePath(guildId + ".banner");
        return bannerFile.exists;
    }

    /**
     * Get system status
     */
    public static function getStatus():Object {
        initCacheDirectory();

        var bannerCount:int = 0;
        var totalSize:Number = 0;

        try {
            var files:Array = _cacheDirectory.getDirectoryListing();
            for each (var file:File in files) {
                if (file.extension == "banner") {
                    bannerCount++;
                    totalSize += file.size;
                }
            }
        } catch (error:Error) {
            trace("BulkBannerSystem: Error getting status - " + error.message);
        }

        return {
            totalBanners: bannerCount,
            totalSizeKB: Math.round(totalSize / 1024 * 100) / 100,
            downloading: _downloading,
            queuedDownloads: _downloadQueue.length,
            manifestEntries: getObjectKeyCount(_bannerManifest)
        };
    }

    /**
     * Get authentication data
     */
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
            trace("BulkBannerSystem: Error getting auth data - " + error.message);
        }

        return {
            guid: "",
            password: ""
        };
    }
    public static function getHexData(guildId:int):String {
        // Check memory cache first
        if (_hexCache[guildId]) {
            return _hexCache[guildId];
        }

        // Try reading from file
        initCacheDirectory();
        var bannerFile:File = _cacheDirectory.resolvePath(guildId + ".banner");

        if (!bannerFile.exists) return null;

        try {
            var fileStream:FileStream = new FileStream();
            fileStream.open(bannerFile, FileMode.READ);
            var hexData:String = fileStream.readUTFBytes(fileStream.bytesAvailable);
            fileStream.close();

            // Cache in memory for next time
            _hexCache[guildId] = hexData;
            return hexData;

        } catch (error:Error) {
            trace("BulkBannerSystem: Error reading hex data for guild " + guildId + " - " + error.message);
            return null;
        }
    }
    private static function getObjectKeyCount(obj:Object):int {
        var count:int = 0;
        for (var key:String in obj) {
            count++;
        }
        return count;
    }
}
}