package kabam.rotmg.CustomGuildBanners {
import flash.display.Sprite;
import flash.display.Graphics;
import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.events.MouseEvent;
import flash.events.Event;
import flash.events.FocusEvent;
import flash.events.KeyboardEvent;
import flash.geom.Point;
import flash.geom.Matrix;
import flash.display.GradientType;
import flash.display.SpreadMethod;
import flash.text.TextField;
import flash.text.TextFormat;
import flash.text.TextFieldType;
import flash.ui.Keyboard;

public class ColorPicker extends Sprite {
    private var colorWheel:Sprite;
    private var brightnessSlider:Sprite;
    private var colorPreview:Sprite;
    private var selectedColorDisplay:Sprite;
    private var hexInput:TextField;
    private var hexLabel:TextField;
    private var isUserEditingHex:Boolean = false;

    private var _selectedColor:uint = 0xFF0000;
    private var currentHue:Number = 0;
    private var currentSaturation:Number = 1;
    private var currentBrightness:Number = 1;

    private const WHEEL_RADIUS:Number = 60;
    private const WHEEL_CENTER_X:Number = 90; // Centered in panel
    private const WHEEL_CENTER_Y:Number = 90; // Centered in panel
    private const SLIDER_WIDTH:Number = 15;
    private const SLIDER_HEIGHT:Number = 120;
    private const SLIDER_X:Number = 155; // Positioned to the right of wheel
    private const SLIDER_Y:Number = 30;  // Centered vertically

    public function ColorPicker() {
        super();
        createColorWheel();
        createBrightnessSlider();
        createColorPreview();
        createSelectedColorDisplay();
        createHexInput();
        // Only set initial hex value, don't auto-update during editing
        updateHexInput();
    }

    public function get selectedColor():uint {
        return _selectedColor;
    }

    private function createColorWheel():void {
        colorWheel = new Sprite();

        var g:Graphics = colorWheel.graphics;
        var colors:Array = [];
        var alphas:Array = [];
        var ratios:Array = [];
        var matrix:Matrix = new Matrix();

        // Create color wheel with hue gradient
        for (var i:int = 0; i < 360; i += 10) {
            var hue:Number = i;
            var color:uint = HSVtoRGB(hue, 1, 1);
            colors.push(color);
            alphas.push(1);
            ratios.push((i / 360) * 255);
        }

        // Draw the color wheel as segments
        var angleStep:Number = (Math.PI * 2) / 36;
        for (var j:int = 0; j < 36; j++) {
            var startAngle:Number = j * angleStep;
            var endAngle:Number = (j + 1) * angleStep;
            var hueValue:Number = (j / 36) * 360;
            var segmentColor:uint = HSVtoRGB(hueValue, 1, 1);

            g.beginFill(segmentColor);
            g.moveTo(WHEEL_CENTER_X, WHEEL_CENTER_Y);
            g.lineTo(
                    WHEEL_CENTER_X + Math.cos(startAngle) * WHEEL_RADIUS,
                    WHEEL_CENTER_Y + Math.sin(startAngle) * WHEEL_RADIUS
            );

            // Draw arc
            var steps:int = 5;
            for (var k:int = 1; k <= steps; k++) {
                var angle:Number = startAngle + (endAngle - startAngle) * (k / steps);
                g.lineTo(
                        WHEEL_CENTER_X + Math.cos(angle) * WHEEL_RADIUS,
                        WHEEL_CENTER_Y + Math.sin(angle) * WHEEL_RADIUS
                );
            }
            g.lineTo(WHEEL_CENTER_X, WHEEL_CENTER_Y);
            g.endFill();
        }

        // Add saturation gradient overlay
        matrix.createGradientBox(WHEEL_RADIUS * 2, WHEEL_RADIUS * 2, 0, WHEEL_CENTER_X - WHEEL_RADIUS, WHEEL_CENTER_Y - WHEEL_RADIUS);
        g.beginGradientFill(GradientType.RADIAL, [0xFFFFFF, 0xFFFFFF], [0, 1], [0, 255], matrix);
        g.drawCircle(WHEEL_CENTER_X, WHEEL_CENTER_Y, WHEEL_RADIUS);
        g.endFill();

        colorWheel.addEventListener(MouseEvent.CLICK, onColorWheelClick);
        addChild(colorWheel);
    }

    private function createBrightnessSlider():void {
        brightnessSlider = new Sprite();
        brightnessSlider.x = SLIDER_X;
        brightnessSlider.y = SLIDER_Y;

        var g:Graphics = brightnessSlider.graphics;
        var matrix:Matrix = new Matrix();
        matrix.createGradientBox(SLIDER_WIDTH, SLIDER_HEIGHT, Math.PI / 2);

        g.beginGradientFill(
                GradientType.LINEAR,
                [0x000000, 0xFFFFFF],
                [1, 1],
                [0, 255],
                matrix
        );
        g.drawRect(0, 0, SLIDER_WIDTH, SLIDER_HEIGHT);
        g.endFill();

        brightnessSlider.addEventListener(MouseEvent.CLICK, onBrightnessSliderClick);
        addChild(brightnessSlider);
    }

    private function createColorPreview():void {
        colorPreview = new Sprite();
        selectedColorDisplay = new Sprite();

        // Position in top-left corner of the panel
        colorPreview.x = 10;
        colorPreview.y = 10;

        updateColorPreview();
        addChild(colorPreview);
    }

    private function createSelectedColorDisplay():void {
        var g:Graphics = selectedColorDisplay.graphics;
        g.beginFill(_selectedColor);
        g.lineStyle(2, 0x2A2A2A);
        g.drawRoundRect(0, 0, 24, 24, 4);
        g.endFill();

        colorPreview.addChild(selectedColorDisplay);
    }

    private function createHexInput():void {
        // Create label
        hexLabel = new TextField();
        hexLabel.text = "Hex:";
        hexLabel.selectable = false;
        hexLabel.x = 30;
        hexLabel.y = WHEEL_CENTER_Y + WHEEL_RADIUS + 15;
        hexLabel.width = 30;
        hexLabel.height = 20;

        var labelFormat:TextFormat = new TextFormat();
        labelFormat.color = 0x000000;
        labelFormat.size = 12;
        labelFormat.font = "Arial";
        hexLabel.setTextFormat(labelFormat);
        hexLabel.defaultTextFormat = labelFormat;

        addChild(hexLabel);

        // Create hex input field
        hexInput = new TextField();
        hexInput.type = TextFieldType.INPUT;
        hexInput.border = true;
        hexInput.borderColor = 0x2A2A2A;
        hexInput.background = true;
        hexInput.backgroundColor = 0xFFFFFF;
        hexInput.x = 65;
        hexInput.y = WHEEL_CENTER_Y + WHEEL_RADIUS + 15;
        hexInput.width = 70;
        hexInput.height = 20;
        hexInput.maxChars = 6;
        hexInput.restrict = "0-9A-Fa-f";

        var inputFormat:TextFormat = new TextFormat();
        inputFormat.color = 0x000000;
        inputFormat.size = 12;
        inputFormat.font = "Arial";
        hexInput.setTextFormat(inputFormat);
        hexInput.defaultTextFormat = inputFormat;

        hexInput.addEventListener(Event.CHANGE, onHexInputChange);
        hexInput.addEventListener(KeyboardEvent.KEY_DOWN, onHexInputKeyDown);
        hexInput.addEventListener(FocusEvent.FOCUS_IN, onHexInputFocusIn);
        hexInput.addEventListener(FocusEvent.FOCUS_OUT, onHexInputFocusOut);

        addChild(hexInput);
    }

    private function onColorWheelClick(e:MouseEvent):void {
        var localPoint:Point = colorWheel.globalToLocal(new Point(e.stageX, e.stageY));
        var dx:Number = localPoint.x - WHEEL_CENTER_X;
        var dy:Number = localPoint.y - WHEEL_CENTER_Y;
        var distance:Number = Math.sqrt(dx * dx + dy * dy);

        if (distance <= WHEEL_RADIUS) {
            currentHue = (Math.atan2(dy, dx) * 180 / Math.PI + 360) % 360;
            currentSaturation = Math.min(1 - (distance / WHEEL_RADIUS), 1)

            updateSelectedColor();
            if (!isUserEditingHex) {
                updateHexInput();
            }
            dispatchEvent(new Event("colorSelected"));
        }
    }

    private function onBrightnessSliderClick(e:MouseEvent):void {
        var localPoint:Point = brightnessSlider.globalToLocal(new Point(e.stageX, e.stageY));
        currentBrightness = Math.max(0, Math.min(1, localPoint.y / SLIDER_HEIGHT));

        updateSelectedColor();
        if (!isUserEditingHex) {
            updateHexInput();
        }
        dispatchEvent(new Event("colorSelected"));
    }

    private function onHexInputChange(e:Event):void {
        // Don't auto-update while user is typing, but do update preview
        isUserEditingHex = true;
        updatePreviewFromHex();
    }

    private function onHexInputKeyDown(e:KeyboardEvent):void {
        if (e.keyCode == Keyboard.ENTER) {
            validateAndUpdateFromHex();
            stage.focus = null; // Remove focus from input
            isUserEditingHex = false;
        }
    }

    private function onHexInputFocusIn(e:FocusEvent):void {
        isUserEditingHex = true;
    }

    private function onHexInputFocusOut(e:FocusEvent):void {
        validateAndUpdateFromHex();
        isUserEditingHex = false;
    }

    private function updatePreviewFromHex():void {
        var hexText:String = hexInput.text.toUpperCase();

        // Remove any non-hex characters
        hexText = hexText.replace(/[^0-9A-F]/g, "");

        var previewColor:uint = 0x000000; // Default to black

        if (hexText.length == 6) {
            var newColor:uint = parseInt("0x" + hexText, 16);
            if (!isNaN(newColor)) {
                previewColor = newColor;
            }
        } else if (hexText.length == 3) {
            // Handle short hex format (e.g., "F0A" -> "FF00AA")
            var expandedHex:String = "";
            for (var i:int = 0; i < 3; i++) {
                expandedHex += hexText.charAt(i) + hexText.charAt(i);
            }
            var newColor3:uint = parseInt("0x" + expandedHex, 16);
            if (!isNaN(newColor3)) {
                previewColor = newColor3;
            }
        }

        // Update preview without changing internal color values
        var g:Graphics = selectedColorDisplay.graphics;
        g.clear();
        g.beginFill(previewColor);
        g.lineStyle(2, 0x2A2A2A);
        g.drawRoundRect(0, 0, 24, 24, 4);
        g.endFill();
    }

    private function validateAndUpdateFromHex():void {
        var hexText:String = hexInput.text.toUpperCase();

        // Remove any non-hex characters that might have slipped through
        hexText = hexText.replace(/[^0-9A-F]/g, "");

        if (hexText.length == 6) {
            var newColor:uint = parseInt("0x" + hexText, 16);

            if (!isNaN(newColor)) {
                _selectedColor = newColor;
                updateHSVFromColor(newColor);
                updateColorPreview();
                // Update the text field to show cleaned hex
                hexInput.text = hexText;
                dispatchEvent(new Event("colorSelected"));
            }
        } else if (hexText.length == 3) {
            // Handle short hex format (e.g., "F0A" -> "FF00AA")
            var expandedHex:String = "";
            for (var i:int = 0; i < 3; i++) {
                expandedHex += hexText.charAt(i) + hexText.charAt(i);
            }
            hexText = expandedHex;

            var newColor3:uint = parseInt("0x" + hexText, 16);
            if (!isNaN(newColor3)) {
                _selectedColor = newColor3;
                updateHSVFromColor(newColor3);
                updateColorPreview();
                // Update the text field to show expanded hex
                hexInput.text = hexText;
                dispatchEvent(new Event("colorSelected"));
            }
        }
        // If invalid length or format, don't update anything - let user continue editing
    }

    private function updateHSVFromColor(color:uint):void {
        var r:Number = ((color >> 16) & 0xFF) / 255;
        var g:Number = ((color >> 8) & 0xFF) / 255;
        var b:Number = (color & 0xFF) / 255;

        var max:Number = Math.max(r, Math.max(g, b));
        var min:Number = Math.min(r, Math.min(g, b));
        var delta:Number = max - min;

        // Brightness
        currentBrightness = max;

        // Saturation
        if (max == 0) {
            currentSaturation = 0;
        } else {
            currentSaturation = delta / max;
        }

        // Hue
        if (delta == 0) {
            currentHue = 0;
        } else if (max == r) {
            currentHue = 60 * (((g - b) / delta) % 6);
        } else if (max == g) {
            currentHue = 60 * (((b - r) / delta) + 2);
        } else {
            currentHue = 60 * (((r - g) / delta) + 4);
        }

        if (currentHue < 0) {
            currentHue += 360;
        }
    }

    private function updateSelectedColor():void {
        _selectedColor = HSVtoRGB(currentHue, currentSaturation, currentBrightness);
        updateColorPreview();
    }

    private function updateColorPreview():void {
        var g:Graphics = selectedColorDisplay.graphics;
        g.clear();
        g.beginFill(_selectedColor);
        g.lineStyle(2, 0x2A2A2A);
        g.drawRoundRect(0, 0, 24, 24, 4);
        g.endFill();
    }

    private function updateHexInput():void {
        var hexString:String = _selectedColor.toString(16).toUpperCase();
        while (hexString.length < 6) {
            hexString = "0" + hexString;
        }
        hexInput.text = hexString;
    }

    private function HSVtoRGB(h:Number, s:Number, v:Number):uint {
        var r:Number, g:Number, b:Number;
        var i:int = Math.floor(h / 60);
        var f:Number = h / 60 - i;
        var p:Number = v * (1 - s);
        var q:Number = v * (1 - s * f);
        var t:Number = v * (1 - s * (1 - f));

        switch (i % 6) {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            case 5: r = v; g = p; b = q; break;
        }

        return (Math.floor(r * 255) << 16) | (Math.floor(g * 255) << 8) | Math.floor(b * 255);
    }


}
}