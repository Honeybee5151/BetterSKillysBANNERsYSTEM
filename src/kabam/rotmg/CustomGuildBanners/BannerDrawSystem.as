package kabam.rotmg.CustomGuildBanners {
import flash.display.Sprite;
import flash.display.Graphics;
import flash.events.MouseEvent;
import flash.events.KeyboardEvent;
import flash.events.Event;
import flash.ui.Keyboard;
import flash.display.Shape;
import flash.geom.Point;

import kabam.rotmg.CustomGuildBanners.ColorPicker;

public class BannerDrawSystem extends Sprite {

    private var banner:Sprite;
    private var pixelGrid:Array;
    private var gridSprites:Array;
    private var isDrawing:Boolean = false;
    private var isErasing:Boolean = false;
    private var colorPicker:ColorPicker;

    // Grid dimensions
    private var gridCols:Number = 20;
    private var gridRows:Number = 32;
    private var pixelSize:Number = 15;

    // Banner dimensions
    private var bannerWidth:Number;
    private var bannerHeight:Number;
    private var shaftWidth:Number = 20;
    private var shaftHeight:Number = 100;

    // Current drawing color (gets from color picker)
    private var currentColor:uint = 0xFF0000; // Red default

    public function BannerDrawSystem(colorPickerRef:ColorPicker = null) {
        colorPicker = colorPickerRef;

        // Activate the utility methods and ensure color system is connected
        if (colorPickerRef) {
            setColorPicker(colorPickerRef);
            currentColor = getCurrentColor(); // Set initial color from picker
        }

        if (stage) {
            init();
        } else {
            addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        }
    }

    private function onAddedToStage(e:Event):void {
        removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
        init();
    }

    private function init():void {
        // Calculate banner dimensions based on grid
        bannerWidth = gridCols * pixelSize;
        bannerHeight = gridRows * pixelSize;

        // Create the main banner container
        banner = new Sprite();
        addChild(banner);

        // Center the banner on screen
        banner.x = (800 - bannerWidth) / 2;
        banner.y = (600 - (bannerHeight + shaftHeight)) / 2;

        // Create banner background and shaft
        createBannerShape();

        // Initialize pixel grid data
        initializeGrid();

        // Create visual grid
        createVisualGrid();

        // Add event listeners
        banner.addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        banner.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, onRightMouseDown);
        if (stage) {
            stage.addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
            stage.addEventListener(MouseEvent.RIGHT_MOUSE_UP, onRightMouseUp);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onMouseMove);
            stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);

            // Enable keyboard focus
            stage.focus = this;
        }
    }

    private function createBannerShape():void {
        var bannerBg:Shape = new Shape();
        var g:Graphics = bannerBg.graphics;

        // Banner background (light beige/cream color)
        g.beginFill(0xF5F5DC);
        g.lineStyle(2, 0x8B4513); // Brown border

        // Main banner rectangle
        g.drawRect(-5, -5, bannerWidth + 10, bannerHeight + 10);

        // Banner decorative top (slight notches)
        g.beginFill(0xF5F5DC);
        g.moveTo(0, 0);
        g.lineTo(bannerWidth * 0.2, 0);
        g.lineTo(bannerWidth * 0.25, -8);
        g.lineTo(bannerWidth * 0.75, -8);
        g.lineTo(bannerWidth * 0.8, 0);
        g.lineTo(bannerWidth, 0);
        g.lineTo(bannerWidth, -5);
        g.lineTo(0, -5);
        g.lineTo(0, 0);
        g.endFill();

        // Banner bottom points (typical banner shape)
        g.beginFill(0xF5F5DC);
        g.moveTo(0, bannerHeight);
        g.lineTo(bannerWidth * 0.4, bannerHeight);
        g.lineTo(bannerWidth * 0.5, bannerHeight + 15);
        g.lineTo(bannerWidth * 0.6, bannerHeight);
        g.lineTo(bannerWidth, bannerHeight);
        g.lineTo(bannerWidth, bannerHeight + 5);
        g.lineTo(0, bannerHeight + 5);
        g.lineTo(0, bannerHeight);
        g.endFill();

        // Create shaft
        var shaft:Shape = new Shape();
        shaft.graphics.beginFill(0x8B4513); // Brown shaft
        shaft.graphics.lineStyle(2, 0x654321); // Darker brown border
        shaft.graphics.drawRect(bannerWidth - shaftWidth - 5, bannerHeight + 5, shaftWidth, shaftHeight);
        shaft.graphics.endFill();

        banner.addChild(bannerBg);
        banner.addChild(shaft);
    }

    private function initializeGrid():void {
        pixelGrid = new Array();
        gridSprites = new Array();

        for (var row:int = 0; row < gridRows; row++) {
            pixelGrid[row] = new Array();
            gridSprites[row] = new Array();

            for (var col:int = 0; col < gridCols; col++) {
                pixelGrid[row][col] = 0; // 0 = empty, color value = filled
                gridSprites[row][col] = null;
            }
        }
    }

    private function createVisualGrid():void {
        var gridContainer:Sprite = new Sprite();
        banner.addChild(gridContainer);

        // Draw grid lines (subtle)
        var gridLines:Shape = new Shape();
        gridLines.graphics.lineStyle(0.5, 0xCCCCCC, 0.3);

        // Vertical lines
        for (var col:int = 0; col <= gridCols; col++) {
            gridLines.graphics.moveTo(col * pixelSize, 0);
            gridLines.graphics.lineTo(col * pixelSize, bannerHeight);
        }

        // Horizontal lines
        for (var row:int = 0; row <= gridRows; row++) {
            gridLines.graphics.moveTo(0, row * pixelSize);
            gridLines.graphics.lineTo(bannerWidth, row * pixelSize);
        }

        gridContainer.addChild(gridLines);
    }

    private function onMouseDown(e:MouseEvent):void {
        if (isPointInBanner(e.localX, e.localY)) {
            isDrawing = true;
            isErasing = false;
            drawOrErasePixel(e.localX, e.localY);
        }
    }

    private function onRightMouseDown(e:MouseEvent):void {
        if (isPointInBanner(e.localX, e.localY)) {
            isErasing = true;
            isDrawing = false;
            drawOrErasePixel(e.localX, e.localY);
        }
    }

    private function onMouseUp(e:MouseEvent):void {
        isDrawing = false;
    }

    private function onRightMouseUp(e:MouseEvent):void {
        isErasing = false;
    }

    private function onMouseMove(e:MouseEvent):void {
        if ((isDrawing || isErasing) && isPointInBanner(e.localX, e.localY)) {
            drawOrErasePixel(e.localX, e.localY);
        }
    }

    private function onKeyDown(e:KeyboardEvent):void {
        if (e.keyCode == Keyboard.E) {
            isErasing = true;
        }
    }

    private function onKeyUp(e:KeyboardEvent):void {
        if (e.keyCode == Keyboard.E) {
            isErasing = false;
        }
    }

    private function isPointInBanner(x:Number, y:Number):Boolean {
        return (x >= 0 && x < bannerWidth && y >= 0 && y < bannerHeight);
    }

    private function drawOrErasePixel(x:Number, y:Number):void {
        var col:int = Math.floor(x / pixelSize);
        var row:int = Math.floor(y / pixelSize);

        // Bounds check
        if (col < 0 || col >= gridCols || row < 0 || row >= gridRows) {
            return;
        }

        if (isErasing) {
            // Erase pixel
            if (pixelGrid[row][col] != 0) {
                pixelGrid[row][col] = 0;

                // Remove visual pixel if it exists
                if (gridSprites[row][col] != null) {
                    banner.removeChild(gridSprites[row][col]);
                    gridSprites[row][col] = null;
                }
            }
        } else if (isDrawing) {
            // Get current color from color picker if available
            if (colorPicker) {
                currentColor = colorPicker.selectedColor;
            }

            // Draw pixel only if it's different from current pixel
            if (pixelGrid[row][col] != currentColor) {
                // Remove old pixel if it exists
                if (gridSprites[row][col] != null) {
                    banner.removeChild(gridSprites[row][col]);
                }

                pixelGrid[row][col] = currentColor;

                // Create visual pixel
                var pixelSprite:Shape = new Shape();
                pixelSprite.graphics.beginFill(currentColor);
                pixelSprite.graphics.lineStyle(1, 0x000000, 0.2);
                pixelSprite.graphics.drawRect(col * pixelSize, row * pixelSize, pixelSize, pixelSize);
                pixelSprite.graphics.endFill();

                banner.addChild(pixelSprite);
                gridSprites[row][col] = pixelSprite;
            }
        }
    }

    // Method to set color picker reference (if not set in constructor)
    public function setColorPicker(colorPickerRef:ColorPicker):void {
        colorPicker = colorPickerRef;
    }

    // Method to get current drawing color
    public function getCurrentColor():uint {
        if (colorPicker) {
            return colorPicker.selectedColor;
        }
        return currentColor;
    }

    // Method to clear entire banner
    public function clearBanner():void {
        for (var row:int = 0; row < gridRows; row++) {
            for (var col:int = 0; col < gridCols; col++) {
                if (gridSprites[row][col] != null) {
                    banner.removeChild(gridSprites[row][col]);
                    gridSprites[row][col] = null;
                }
                pixelGrid[row][col] = 0;
            }
        }
    }

    // Method to get banner data (for saving/loading)
    public function getBannerData():Array {
        return pixelGrid;
    }

    // Method to load banner data
    public function loadBannerData(data:Array):void {
        clearBanner();

        for (var row:int = 0; row < gridRows && row < data.length; row++) {
            for (var col:int = 0; col < gridCols && col < data[row].length; col++) {
                if (data[row][col] != 0) {
                    pixelGrid[row][col] = data[row][col];

                    var pixelSprite:Shape = new Shape();
                    pixelSprite.graphics.beginFill(data[row][col]);
                    pixelSprite.graphics.lineStyle(1, 0x000000, 0.2);
                    pixelSprite.graphics.drawRect(col * pixelSize, row * pixelSize, pixelSize, pixelSize);
                    pixelSprite.graphics.endFill();

                    banner.addChild(pixelSprite);
                    gridSprites[row][col] = pixelSprite;
                }
            }
        }
    }




}
}