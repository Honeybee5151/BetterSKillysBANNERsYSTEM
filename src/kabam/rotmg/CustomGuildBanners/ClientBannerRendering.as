package kabam.rotmg.CustomGuildBanners {
import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.geom.Rectangle;

public class ClientBannerRendering {

    private static var _bannerCache:Object = {};
    private static var _cacheUsageOrder:Array = []; // Track usage for LRU eviction
    private static const MAX_CACHE_SIZE:int = 100; // Increased limit
    private static const MEMORY_LIMIT_MB:int = 50; // Memory-based limit

    /**
     * Improved cache with LRU (Least Recently Used) eviction
     */
    private static function cacheBannerTexture(cacheKey:String, bitmapData:BitmapData):void {
        // Remove from old position if it exists
        var existingIndex:int = _cacheUsageOrder.indexOf(cacheKey);
        if (existingIndex >= 0) {
            _cacheUsageOrder.splice(existingIndex, 1);
        }

        // Add to front (most recently used)
        _cacheUsageOrder.unshift(cacheKey);

        // Check if we need to free memory
        while (_cacheUsageOrder.length > MAX_CACHE_SIZE || isMemoryLimitExceeded()) {
            evictOldestBanner();
        }

        _bannerCache[cacheKey] = bitmapData.clone();
        trace("ClientBannerRendering: Cached banner " + cacheKey + " (total: " + _cacheUsageOrder.length + ")");
    }

    /**
     * Remove the least recently used banner
     */
    private static function evictOldestBanner():void {
        if (_cacheUsageOrder.length == 0) return;

        var oldestKey:String = _cacheUsageOrder.pop(); // Remove from end (oldest)
        var oldBitmapData:BitmapData = _bannerCache[oldestKey];

        if (oldBitmapData) {
            oldBitmapData.dispose(); // Free memory
            delete _bannerCache[oldestKey];
            trace("ClientBannerRendering: Evicted old banner " + oldestKey);
        }
    }

    /**
     * Check if memory usage is too high (rough estimate)
     */
    private static function isMemoryLimitExceeded():Boolean {
        var estimatedMB:Number = (_cacheUsageOrder.length * 0.65); // ~650KB per banner
        return estimatedMB > MEMORY_LIMIT_MB;
    }

    /**
     * Updated render function with better cache management
     */
    public static function renderBannerFromHex(bannerData:String, pixelSize:int = 16):Bitmap {
        var cacheKey:String = generateCacheKey(bannerData, pixelSize);

        // Check cache and update usage order
        if (_bannerCache[cacheKey]) {
            updateCacheUsage(cacheKey); // Move to front of usage list
            trace("ClientBannerRendering: Using cached banner texture");
            var cachedBitmapData:BitmapData = _bannerCache[cacheKey];
            return new Bitmap(cachedBitmapData.clone());
        }

        // Not in cache, create new one
        var colors:Array = ClientBannerRendering.parseBannerData(bannerData);
        var bitmapData:BitmapData = ClientBannerRendering.createBannerBitmap(colors, pixelSize);

        // Cache it
        cacheBannerTexture(cacheKey, bitmapData);

        return new Bitmap(bitmapData);
    }

    /**
     * Generate a shorter cache key to save memory
     */
    private static function generateCacheKey(bannerData:String, pixelSize:int):String {
        // Use a hash of the banner data instead of storing the full hex string
        var hash:int = simpleHash(bannerData);
        return hash.toString(16) + "_" + pixelSize;
    }

    /**
     * Simple hash function for banner data
     */
    private static function simpleHash(str:String):int {
        var hash:int = 0;
        for (var i:int = 0; i < str.length; i++) {
            hash = ((hash << 5) - hash + str.charCodeAt(i)) & 0xFFFFFF;
        }
        return hash;
    }

    /**
     * Update cache usage order
     */
    private static function updateCacheUsage(cacheKey:String):void {
        var index:int = _cacheUsageOrder.indexOf(cacheKey);
        if (index >= 0) {
            _cacheUsageOrder.splice(index, 1); // Remove from current position
            _cacheUsageOrder.unshift(cacheKey); // Add to front
        }
    }

    /**
     * Get cache statistics
     */
    public static function getCacheStats():Object {
        return {
            totalCached: _cacheUsageOrder.length,
            maxSize: MAX_CACHE_SIZE,
            estimatedMemoryMB: Math.round(_cacheUsageOrder.length * 0.65 * 100) / 100,
            memoryLimitMB: MEMORY_LIMIT_MB
        };
    }

    public static function parseBannerData(hexData:String):Array {
        var result:Array = [];
        // These should match your grid constants
        var rows:int = 32; // or use a class constant
        var cols:int = 20;

        var i:int = 0;
        for (var row:int = 0; row < rows; row++) {
            var rowArr:Array = [];
            for (var col:int = 0; col < cols; col++) {
                // Each color is 6 chars
                var hexColor:String = hexData.substr(i, 6);
                var color:uint = uint("0x" + hexColor);
                rowArr.push(color);
                i += 6;
            }
            result.push(rowArr);
        }
        return result;
    }

    public static function createBannerBitmap(colors:Array, pixelSize:int):BitmapData {
        // Assume colors is a 2D Array [row][col], each value is a uint color (0xRRGGBB)
        var rows:int = colors.length;
        var cols:int = colors[0].length;
        var bmp:BitmapData = new BitmapData(cols * pixelSize, rows * pixelSize, false, 0x000000);

        for (var row:int = 0; row < rows; row++) {
            for (var col:int = 0; col < cols; col++) {
                var color:uint = colors[row][col];
                var rect:Rectangle = new Rectangle(col * pixelSize, row * pixelSize, pixelSize, pixelSize);
                bmp.fillRect(rect, color);
            }
        }
        return bmp;
    }
}
}