package kabam.rotmg.CustomGuildBanners {
import flash.display.Sprite;
import flash.display.Shape;

import kabam.rotmg.appengine.api.AppEngineClient;
import kabam.rotmg.core.StaticInjectorContext;

import flash.display.Bitmap;
import flash.events.Event;
import flash.utils.Timer;
import flash.events.TimerEvent;

import kabam.rotmg.account.core.Account;

public class BannerRetrievalSystem {

    // Request queue system
    private static var _requestQueue:Array = [];
    private static var _processingRequest:Boolean = false;
    private static var _currentClient:AppEngineClient = null;

    // Track pending requests for timeout handling
    private static var _pendingRequests:Object = {};
    private static var _timers:Object = {};
    private static const REQUEST_TIMEOUT:int = 10000; // 10 seconds

    /**
     * Request a guild's banner from the server and render it
     * This now uses a queue system to handle multiple requests properly
     * Returns a vector Shape for perfect scaling
     */
    public static function requestGuildBanner(guildId:int, callback:Function, pixelSize:int = 16, player:* = null):void {
        trace("BannerRetrievalSystem: Queueing banner request for guild " + guildId);

        // Create unique request ID
        var requestId:String = "banner_" + guildId + "_" + new Date().time;

        // Create request object
        var request:Object = {
            requestId: requestId,
            guildId: guildId,
            callback: callback,
            pixelSize: pixelSize,
            player: player,
            requestTime: new Date().time
        };

        // Add to queue
        _requestQueue.push(request);

        // Start processing if not already processing
        if (!_processingRequest) {
            processNextRequest();
        }
    }

    /**
     * Process the next request in the queue
     */
    private static function processNextRequest():void {
        if (_requestQueue.length == 0) {
            _processingRequest = false;
            trace("BannerRetrievalSystem: Queue empty, stopping processing");
            return;
        }

        _processingRequest = true;
        var request:Object = _requestQueue.shift(); // Get first request

        trace("BannerRetrievalSystem: Processing request " + request.requestId + " for guild " + request.guildId);

        // Store request for timeout handling
        _pendingRequests[request.requestId] = request;

        // Set timeout
        var timerId:int = setTimeout(function ():void {
            handleRequestTimeout(request.requestId);
        }, REQUEST_TIMEOUT);
        _timers[request.requestId] = timerId;

        // Get authentication info
        var authData:Object = getAuthenticationData(request.player);

        // Prepare request data
        var requestData:Object = {
            guid: authData.guid,
            password: authData.password,
            guildId: request.guildId,
            requestId: request.requestId
        };

        // Send request to server
        try {
            _currentClient = StaticInjectorContext.getInjector().getInstance(AppEngineClient);

            // Set up callback BEFORE sending request
            _currentClient.complete.addOnce(function (success:Boolean, data:String):void {
                handleNetworkResponse(success, data, request.requestId);
            });

            _currentClient.sendRequest("/guild/getGuildBanner", requestData);
            trace("BannerRetrievalSystem: Sent request " + request.requestId);

        } catch (error:Error) {
            trace("BannerRetrievalSystem: Error sending request - " + error.message);
            finishRequest(request.requestId, false, null);
        }
    }

    /**
     * Handle network response
     */
    private static function handleNetworkResponse(success:Boolean, data:String, expectedRequestId:String):void {
        trace("BannerRetrievalSystem: Received network response for request " + expectedRequestId);

        if (success && data) {
            try {
                var response:Object = JSON.parse(data);
                handleBannerResponse(response, expectedRequestId);
            } catch (error:Error) {
                trace("BannerRetrievalSystem: Error parsing response - " + error.message);
                finishRequest(expectedRequestId, false, null);
            }
        } else {
            trace("BannerRetrievalSystem: Network request failed for " + expectedRequestId);
            finishRequest(expectedRequestId, false, null);
        }
    }

    /**
     * Handle server response and render the banner
     */
    private static function handleBannerResponse(response:Object, expectedRequestId:String):void {
        try {
            trace("BannerRetrievalSystem: Processing banner response");

            if (!response) {
                trace("BannerRetrievalSystem: Empty response received");
                finishRequest(expectedRequestId, false, null);
                return;
            }

            var guildId:int = response.guildId || 0;
            var success:Boolean = response.success || false;
            var requestId:String = response.requestId || expectedRequestId; // Fallback to expected ID

            // Find the request
            var request:Object = _pendingRequests[expectedRequestId];
            if (!request) {
                trace("BannerRetrievalSystem: No matching request found for " + expectedRequestId);
                finishRequest(expectedRequestId, false, null);
                return;
            }

            if (!success || !response.bannerData) {
                trace("BannerRetrievalSystem: Server returned no banner data for guild " + guildId +
                        " - " + (response.message || "Unknown error"));
                finishRequest(expectedRequestId, false, request);
                return;
            }

            // We have banner data - render it as vector!
            var bannerData:String = response.bannerData;
            trace("BannerRetrievalSystem: Rendering vector banner for guild " + guildId +
                    " (data length: " + bannerData.length + ")");

            // Use ClientBannerRendering to create the vector shape
            var bannerShape:Shape = ClientBannerRendering.renderBannerFromHex(bannerData, request.pixelSize);

            if (bannerShape) {
                trace("BannerRetrievalSystem: Successfully rendered vector banner for guild " + guildId);
                finishRequest(expectedRequestId, true, request, bannerShape);
            } else {
                trace("BannerRetrievalSystem: Failed to render vector banner for guild " + guildId);
                finishRequest(expectedRequestId, false, request);
            }

        } catch (error:Error) {
            trace("BannerRetrievalSystem: Error handling response - " + error.message);
            finishRequest(expectedRequestId, false, null);
        }
    }

    /**
     * Finish processing a request and start the next one
     * Now handles vector Shape objects instead of Bitmap
     */
    private static function finishRequest(requestId:String, success:Boolean, request:Object, bannerShape:Shape = null):void {
        trace("BannerRetrievalSystem: Finishing request " + requestId + " (success: " + success + ")");

        // Call the callback if we have the request
        if (request && request.callback != null) {
            try {
                request.callback(bannerShape, request.guildId);
            } catch (error:Error) {
                trace("BannerRetrievalSystem: Error in callback - " + error.message);
            }
        }

        // Clean up
        cleanupRequest(requestId);

        // Process next request
        processNextRequest();
    }

    /**
     * Handle request timeout
     */
    private static function handleRequestTimeout(requestId:String):void {
        if (_pendingRequests[requestId]) {
            var request:Object = _pendingRequests[requestId];
            trace("BannerRetrievalSystem: Request timeout for guild " + request.guildId);
            finishRequest(requestId, false, request);
        }
    }

    /**
     * Clean up a request and its timeout
     */
    private static function cleanupRequest(requestId:String):void {
        if (_pendingRequests[requestId]) {
            delete _pendingRequests[requestId];
        }
        if (_timers[requestId]) {
            clearTimeout(_timers[requestId]);
            delete _timers[requestId];
        }
    }

    /**
     * Request multiple guild banners (they'll be queued and processed one by one)
     */
    public static function requestMultipleBanners(guildIds:Array, callback:Function, pixelSize:int = 16, player:* = null):void {
        trace("BannerRetrievalSystem: Queueing " + guildIds.length + " guild banners");

        for (var i:int = 0; i < guildIds.length; i++) {
            var guildId:int = guildIds[i];
            requestGuildBanner(guildId, callback, pixelSize, player);
        }
    }

    /**
     * Cancel all pending requests
     */
    public static function cancelAllRequests():void {
        var cancelCount:int = _requestQueue.length;

        // Clear queue
        _requestQueue = [];

        // Clean up any pending request
        for (var requestId:String in _pendingRequests) {
            cleanupRequest(requestId);
        }

        _processingRequest = false;
        _currentClient = null;

        if (cancelCount > 0) {
            trace("BannerRetrievalSystem: Cancelled " + cancelCount + " queued requests");
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
            queuedRequests: _requestQueue.length,
            pendingRequests: pendingCount,
            processing: _processingRequest,
            cacheStats: ClientBannerRendering.getCacheStats()
        };
    }

    // === CONVENIENCE METHODS - Updated for Vector Support ===

    /**
     * Display vector banner at specified position
     */
    public static function displayBannerAt(guildId:int, container:*, x:Number, y:Number, pixelSize:int = 16, player:* = null):void {
        requestGuildBanner(guildId, function (bannerShape:Shape, receivedGuildId:int):void {
            if (bannerShape && container && container.stage) {
                bannerShape.x = x;
                bannerShape.y = y;
                container.addChild(bannerShape);
                trace("BannerRetrievalSystem: Displayed vector banner for guild " + receivedGuildId + " at (" + x + "," + y + ")");
            } else if (!bannerShape) {
                trace("BannerRetrievalSystem: No banner available for guild " + receivedGuildId);
            }
        }, pixelSize, player);
    }

    /**
     * Display scalable vector banner (new method)
     */
    public static function displayScalableBannerAt(guildId:int, container:*, x:Number, y:Number, scale:Number = 1.0, pixelSize:int = 16, player:* = null):void {
        requestGuildBanner(guildId, function (bannerShape:Shape, receivedGuildId:int):void {
            if (bannerShape && container && container.stage) {
                bannerShape.x = x;
                bannerShape.y = y;
                bannerShape.scaleX = scale;
                bannerShape.scaleY = scale;
                container.addChild(bannerShape);
                trace("BannerRetrievalSystem: Displayed scaled vector banner for guild " + receivedGuildId + " at (" + x + "," + y + ") scale=" + scale);
            } else if (!bannerShape) {
                trace("BannerRetrievalSystem: No banner available for guild " + receivedGuildId);
            }
        }, pixelSize, player);
    }

    /**
     * Get banner as Bitmap if needed for legacy compatibility
     */


    /**
     * Display banner with automatic format detection
     */

    private static function getAuthenticationData(player:* = null):Object {
        try {
            var account:Account = StaticInjectorContext.getInjector().getInstance(Account);
            if (account) {
                return {
                    guid: account.getUserId(),
                    password: account.getPassword()
                };
            }
        } catch (error:Error) {
            trace("BannerRetrievalSystem: Error getting auth data - " + error.message);
        }

        return {
            guid: "",
            password: ""
        };
    }

    // === TIMER FUNCTIONS ===

    private static function setTimeout(callback:Function, delay:int):int {
        var timerId:int = Math.random() * 100000;
        var timer:Timer = new Timer(delay, 1);

        timer.addEventListener(TimerEvent.TIMER_COMPLETE, function (e:TimerEvent):void {
            callback();
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE, arguments.callee);
        });

        timer.start();
        return timerId;
    }

    private static function clearTimeout(timerId:int):void {
        // Timer cleanup is handled in the event listener
    }
}
}