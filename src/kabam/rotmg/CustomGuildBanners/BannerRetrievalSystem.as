package kabam.rotmg.CustomGuildBanners {
import kabam.rotmg.appengine.api.AppEngineClient;
import kabam.rotmg.core.StaticInjectorContext;
import flash.display.Bitmap;
import flash.events.Event;

public class BannerRetrievalSystem {

    // Track pending requests and their callbacks
    private static var _pendingRequests:Object = {};
    private static var _requestTimeouts:Object = {};
    private static const REQUEST_TIMEOUT:int = 10000; // 10 seconds

    /**
     * Request a guild's banner from the server and render it
     * @param guildId The guild ID to get the banner for
     * @param callback Function to call when banner is loaded: function(bannerBitmap:Bitmap, guildId:int):void
     * @param pixelSize Size to render the banner (default 16)
     * @param player Player object for authentication
     */
    public static function requestGuildBanner(guildId:int, callback:Function, pixelSize:int = 16, player:* = null):void {
        trace("BannerRetrievalSystem: Requesting banner for guild " + guildId);

        // Create unique request ID
        var requestId:String = "banner_" + guildId + "_" + new Date().time;

        // Store request info
        _pendingRequests[requestId] = {
            guildId: guildId,
            callback: callback,
            pixelSize: pixelSize,
            requestTime: new Date().time
        };

        // Set timeout for request
        setTimeout(function():void {
            handleRequestTimeout(requestId);
        }, REQUEST_TIMEOUT);

        // Get authentication info
        var authData:Object = getAuthenticationData(player);
        if (!authData.guid || !authData.password) {
            trace("BannerRetrievalSystem: Warning - No authentication data available");
            // You might want to handle this case differently
        }

        // Prepare request data
        var requestData:Object = {
            guid: authData.guid,
            password: authData.password,
            guildId: guildId,
            requestId: requestId // Include request ID for matching responses
        };

        // Send request to server
        try {
            var client:AppEngineClient = StaticInjectorContext.getInjector().getInstance(AppEngineClient);
            client.sendRequest("/guild/getGuildBanner", requestData);
            trace("BannerRetrievalSystem: Sent request " + requestId + " for guild " + guildId);
        } catch (error:Error) {
            trace("BannerRetrievalSystem: Error sending request - " + error.message);
            cleanupRequest(requestId);
            if (callback != null) {
                callback(null, guildId); // Call callback with null to indicate failure
            }
        }
        client.complete.addOnce(function(success:Boolean, data:String):void {
            if (success && data) {
                try {
                    var response:Object = JSON.parse(data);
                    handleBannerResponse(response);
                } catch (error:Error) {
                    trace("BannerRetrievalSystem: Error parsing response - " + error.message);
                }
            } else {
                trace("BannerRetrievalSystem: Request failed for guild " + guildId);
            }
        });

    }

    /**
     * Handle server response and render the banner
     * Call this from your network response handler
     * @param response Server response object
     */
    public static function handleBannerResponse(response:Object):void {
        try {
            trace("BannerRetrievalSystem: Received response: " + JSON.stringify(response));

            if (!response) {
                trace("BannerRetrievalSystem: Empty response received");
                return;
            }

            var guildId:int = response.guildId || 0;
            var success:Boolean = response.success || false;
            var requestId:String = response.requestId || "";

            // Find matching request
            var matchingRequest:Object = null;
            var matchingRequestId:String = "";

            // If we have a request ID, use it for exact matching
            if (requestId && _pendingRequests[requestId]) {
                matchingRequest = _pendingRequests[requestId];
                matchingRequestId = requestId;
            } else {
                // Fallback: find by guild ID (for older implementations)
                for (var reqId:String in _pendingRequests) {
                    var req:Object = _pendingRequests[reqId];
                    if (req.guildId == guildId) {
                        matchingRequest = req;
                        matchingRequestId = reqId;
                        break;
                    }
                }
            }

            if (!matchingRequest) {
                trace("BannerRetrievalSystem: No matching request found for guild " + guildId);
                return;
            }

            if (!success || !response.bannerData) {
                trace("BannerRetrievalSystem: Server returned no banner data for guild " + guildId +
                        " - " + (response.message || "Unknown error"));

                // Call callback with null to indicate no banner
                if (matchingRequest.callback != null) {
                    matchingRequest.callback(null, guildId);
                }
                cleanupRequest(matchingRequestId);
                return;
            }

            // We have banner data - render it!
            var bannerData:String = response.bannerData;
            trace("BannerRetrievalSystem: Rendering banner for guild " + guildId +
                    " (data length: " + bannerData.length + ")");

            // Use ClientBannerRendering to create the bitmap
            var bannerBitmap:Bitmap = ClientBannerRendering.renderBannerFromHex(bannerData, matchingRequest.pixelSize);

            if (bannerBitmap) {
                trace("BannerRetrievalSystem: Successfully rendered banner for guild " + guildId);

                // Call the callback with the rendered bitmap
                if (matchingRequest.callback != null) {
                    matchingRequest.callback(bannerBitmap, guildId);
                }
            } else {
                trace("BannerRetrievalSystem: Failed to render banner for guild " + guildId);
                if (matchingRequest.callback != null) {
                    matchingRequest.callback(null, guildId);
                }
            }

            // Clean up the request
            cleanupRequest(matchingRequestId);

        } catch (error:Error) {
            trace("BannerRetrievalSystem: Error handling response - " + error.message);
        }
    }

    /**
     * Request multiple guild banners (for guild lists)
     * @param guildIds Array of guild IDs to fetch
     * @param callback Called for each banner: function(bannerBitmap:Bitmap, guildId:int):void
     * @param pixelSize Size to render banners
     * @param player Player object for authentication
     */
    public static function requestMultipleBanners(guildIds:Array, callback:Function, pixelSize:int = 16, player:* = null):void {
        trace("BannerRetrievalSystem: Requesting " + guildIds.length + " guild banners");

        for (var i:int = 0; i < guildIds.length; i++) {
            var guildId:int = guildIds[i];
            requestGuildBanner(guildId, callback, pixelSize, player);
        }
    }

    /**
     * Convenience method: Request banner and display it at specific coordinates
     * @param guildId Guild ID to fetch
     * @param container Display object to add banner to
     * @param x X position
     * @param y Y position
     * @param pixelSize Banner size
     * @param player Player for authentication
     */
    public static function displayBannerAt(guildId:int, container:*, x:Number, y:Number, pixelSize:int = 16, player:* = null):void {
        requestGuildBanner(guildId, function(bannerBitmap:Bitmap, receivedGuildId:int):void {
            if (bannerBitmap && container && container.stage) {
                bannerBitmap.x = x;
                bannerBitmap.y = y;
                container.addChild(bannerBitmap);
                trace("BannerRetrievalSystem: Displayed banner for guild " + receivedGuildId + " at (" + x + "," + y + ")");
            } else if (!bannerBitmap) {
                trace("BannerRetrievalSystem: No banner available for guild " + receivedGuildId);
            }
        }, pixelSize, player);
    }

    /**
     * Get authentication data from player object
     * You'll need to adapt this to your game's authentication system
     */
    private static function getAuthenticationData(player:* = null):Object {
        // TODO: Adapt this to your actual authentication system
        try {
            if (player) {
                return {
                    guid: player.accountId_ || player.guid_ || "",
                    password: player.password_ || player.token_ || ""
                };
            }
        } catch (error:Error) {
            trace("BannerRetrievalSystem: Error getting auth data - " + error.message);
        }

        // Fallback - you might want to get this from a global auth manager
        return {
            guid: "", // Get from your game's auth system
            password: "" // Get from your game's auth system
        };
    }

    /**
     * Handle request timeout
     */
    private static function handleRequestTimeout(requestId:String):void {
        if (_pendingRequests[requestId]) {
            var request:Object = _pendingRequests[requestId];
            trace("BannerRetrievalSystem: Request timeout for guild " + request.guildId);

            // Call callback with null to indicate timeout
            if (request.callback != null) {
                request.callback(null, request.guildId);
            }

            cleanupRequest(requestId);
        }
    }

    /**
     * Clean up a request and its timeout
     */
    private static function cleanupRequest(requestId:String):void {
        if (_pendingRequests[requestId]) {
            delete _pendingRequests[requestId];
        }
        if (_requestTimeouts[requestId]) {
            clearTimeout(_requestTimeouts[requestId]);
            delete _requestTimeouts[requestId];
        }
    }

    /**
     * Cancel all pending requests (useful when changing screens)
     */
    public static function cancelAllRequests():void {
        var cancelCount:int = 0;
        for (var requestId:String in _pendingRequests) {
            cleanupRequest(requestId);
            cancelCount++;
        }

        if (cancelCount > 0) {
            trace("BannerRetrievalSystem: Cancelled " + cancelCount + " pending requests");
        }
    }

    /**
     * Get system status
     */
    public static function getStatus():Object {
        var pendingCount:int = 0;
        for (var requestId:String in _pendingRequests) {
            pendingCount++;
        }

        return {
            pendingRequests: pendingCount,
            cacheStats: ClientBannerRendering.getCacheStats()
        };
    }

    // Simple setTimeout implementation for ActionScript
    private static function setTimeout(callback:Function, delay:int):int {
        // This is a simplified version - you might want to use Timer class for more accuracy
        var timerId:int = Math.random() * 100000;

        // In a real implementation, you'd use Timer class here
        // For now, this is just a placeholder
        return timerId;
    }

    private static function clearTimeout(timerId:int):void {
        // Placeholder for timeout clearing
    }
}
}