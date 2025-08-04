package kabam.rotmg.CustomGuildBanners {
import flash.display.Graphics;
import flash.display.Shape;
import flash.display.Sprite;
import flash.geom.Matrix;

public class ClientBannerRendering {

    private static var _bannerCache:Object = {};
    private static var _cacheUsageOrder:Array = []; // Track usage for LRU eviction
    private static const MAX_CACHE_SIZE:int = 100; // Increased limit
    private static const MEMORY_LIMIT_MB:int = 30; // Lower since vectors use less memory

    /**
     * Improved cache with LRU (Least Recently Used) eviction
     */
    private static function cacheBannerVector(cacheKey:String, vectorShape:Shape):void {
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

        // Clone the shape for caching
        var clonedShape:Shape = cloneVectorShape(vectorShape);
        _bannerCache[cacheKey] = clonedShape;
        trace("ClientBannerRendering: Cached vector banner " + cacheKey + " (total: " + _cacheUsageOrder.length + ")");
    }

    /**
     * Clone a vector shape for caching
     */
    private static function cloneVectorShape(original:Shape):Shape {
        var clone:Shape = new Shape();
        // We'll need to redraw the graphics since Graphics can't be directly cloned
        // The actual cloning will happen during render when we have the color data
        return clone;
    }

    /**
     * Remove the least recently used banner
     */
    private static function evictOldestBanner():void {
        if (_cacheUsageOrder.length == 0) return;

        var oldestKey:String = _cacheUsageOrder.pop(); // Remove from end (oldest)
        var oldShape:Shape = _bannerCache[oldestKey];

        if (oldShape) {
            oldShape.graphics.clear(); // Clear vector graphics
            delete _bannerCache[oldestKey];
            trace("ClientBannerRendering: Evicted old vector banner " + oldestKey);
        }
    }

    /**
     * Check if memory usage is too high (vectors use less memory)
     */
    private static function isMemoryLimitExceeded():Boolean {
        var estimatedMB:Number = (_cacheUsageOrder.length * 0.2); // ~200KB per vector banner
        return estimatedMB > MEMORY_LIMIT_MB;
    }

    /**
     * Main render function - now returns a vector Shape instead of Bitmap
     */
    public static function renderBannerFromHex(bannerData:String, pixelSize:int = 16):Shape {
        var cacheKey:String = generateCacheKey(bannerData, pixelSize);

        // Check cache and update usage order
        if (_bannerCache[cacheKey]) {
            updateCacheUsage(cacheKey); // Move to front of usage list
            trace("ClientBannerRendering: Using cached vector banner");
            var cachedShape:Shape = _bannerCache[cacheKey];
            return cloneVectorBanner(cachedShape, bannerData, pixelSize);
        }

        // Not in cache, create new vector banner
        var colors:Array = ClientBannerRendering.parseBannerData(bannerData);
        var vectorShape:Shape = ClientBannerRendering.createVectorBanner(colors, pixelSize);

        // Cache it (we'll store the colors data with the key for reconstruction)
        cacheBannerVector(cacheKey, vectorShape);

        return vectorShape;
    }

    /**
     * Create a vector-based banner using Flash Graphics API
     */
    public static function createVectorBanner(colors:Array, pixelSize:int):Shape {
        var rows:int = colors.length;
        var cols:int = colors[0].length;
        var bannerShape:Shape = new Shape();
        var g:Graphics = bannerShape.graphics;

        // Clear any existing graphics
        g.clear();

        // Draw each "pixel" as a vector rectangle
        for (var row:int = 0; row < rows; row++) {
            for (var col:int = 0; col < cols; col++) {
                var color:uint = colors[row][col];

                // Skip transparent/black pixels if desired
                if (color == 0x000000) continue;

                // Set fill color (no stroke for crisp edges)
                g.beginFill(color, 1.0);

                // Draw rectangle for this "pixel"
                var x:Number = col * pixelSize;
                var y:Number = row * pixelSize;
                g.drawRect(x, y, pixelSize, pixelSize);

                g.endFill();
            }
        }

        return bannerShape;
    }

    /**
     * Create an optimized vector banner by grouping adjacent same-colored pixels
     */
    public static function createOptimizedVectorBanner(colors:Array, pixelSize:int):Shape {
        var rows:int = colors.length;
        var cols:int = colors[0].length;
        var bannerShape:Shape = new Shape();
        var g:Graphics = bannerShape.graphics;

        g.clear();

        // Track which pixels have been processed
        var processed:Array = [];
        for (var i:int = 0; i < rows; i++) {
            processed[i] = [];
            for (var j:int = 0; j < cols; j++) {
                processed[i][j] = false;
            }
        }

        // Group adjacent pixels of the same color into larger rectangles
        for (var row:int = 0; row < rows; row++) {
            for (var col:int = 0; col < cols; col++) {
                if (processed[row][col]) continue;

                var color:uint = colors[row][col];
                if (color == 0x000000) {
                    processed[row][col] = true;
                    continue;
                }

                // Find the largest rectangle of this color starting at (row, col)
                var rect:Object = findLargestRect(colors, processed, row, col, color);

                // Draw the optimized rectangle
                g.beginFill(color, 1.0);
                g.drawRect(
                        rect.x * pixelSize,
                        rect.y * pixelSize,
                        rect.width * pixelSize,
                        rect.height * pixelSize
                );
                g.endFill();

                // Mark all pixels in this rectangle as processed
                markRectAsProcessed(processed, rect.x, rect.y, rect.width, rect.height);
            }
        }

        return bannerShape;
    }

    /**
     * Find the largest rectangle of the same color starting at given position
     */
    private static function findLargestRect(colors:Array, processed:Array, startRow:int, startCol:int, targetColor:uint):Object {
        var rows:int = colors.length;
        var cols:int = colors[0].length;

        // Find maximum width from starting position
        var maxWidth:int = 0;
        for (var c:int = startCol; c < cols; c++) {
            if (processed[startRow][c] || colors[startRow][c] != targetColor) {
                break;
            }
            maxWidth++;
        }

        // Find maximum height that maintains the width
        var maxHeight:int = 1;
        for (var r:int = startRow + 1; r < rows; r++) {
            var canExtend:Boolean = true;
            for (var c2:int = startCol; c2 < startCol + maxWidth; c2++) {
                if (processed[r][c2] || colors[r][c2] != targetColor) {
                    canExtend = false;
                    break;
                }
            }
            if (!canExtend) break;
            maxHeight++;
        }

        return {
            x: startCol,
            y: startRow,
            width: maxWidth,
            height: maxHeight
        };
    }

    /**
     * Mark rectangle area as processed
     */
    private static function markRectAsProcessed(processed:Array, x:int, y:int, width:int, height:int):void {
        for (var r:int = y; r < y + height; r++) {
            for (var c:int = x; c < x + width; c++) {
                processed[r][c] = true;
            }
        }
    }

    /**
     * Clone a vector banner (recreate graphics)
     */
    private static function cloneVectorBanner(original:Shape, bannerData:String, pixelSize:int):Shape {
        // Since we can't directly clone Graphics, recreate from data
        var colors:Array = parseBannerData(bannerData);
        return createVectorBanner(colors, pixelSize);
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
            estimatedMemoryMB: Math.round(_cacheUsageOrder.length * 0.2 * 100) / 100,
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

    /**
     * Create a small vector banner (similar to your createSmallBannerBitmap)
     */
    public static function createSmallVectorBanner(colors:Array, pixelSize:int = 1):Shape {
        // Create 10x16 vector banner (half size)
        var width:int = 10;  // GRID_COLS / 2
        var height:int = 16; // GRID_ROWS / 2

        var bannerShape:Shape = new Shape();
        var g:Graphics = bannerShape.graphics;
        g.clear();

        // Sample every other pixel to downscale
        for (var row:int = 0; row < height; row++) {
            for (var col:int = 0; col < width; col++) {
                var sourceRow:int = row * 2;
                var sourceCol:int = col * 2;
                var color:uint = colors[sourceRow][sourceCol];

                if (color != 0x000000) {
                    g.beginFill(color, 1.0);
                    g.drawRect(col * pixelSize, row * pixelSize, pixelSize, pixelSize);
                    g.endFill();
                }
            }
        }

        return bannerShape;
    }

    /**
     * Clear banner cache
     */
    public static function clearBannerCache():void {
        for (var key:String in _bannerCache) {
            var shape:Shape = _bannerCache[key];
            if (shape) {
                shape.graphics.clear(); // Clear vector graphics
            }
            delete _bannerCache[key];
        }

        // Clear the usage order array too
        _cacheUsageOrder = [];

        trace("ClientBannerRendering: Vector banner cache cleared");
    }



}
}