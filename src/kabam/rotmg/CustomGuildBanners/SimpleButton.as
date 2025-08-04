package kabam.rotmg.CustomGuildBanners {
import flash.display.Sprite;
import flash.display.Graphics;
import flash.events.MouseEvent;
import flash.events.Event;
import flash.text.TextField;
import flash.text.TextFormat;
import flash.text.TextFieldAutoSize;

public class SimpleButton extends Sprite {

    private var buttonBg:Sprite;
    private var buttonText:TextField;
    private var buttonWidth:Number;
    private var buttonHeight:Number;
    private var _enabled:Boolean = true;

    // Colors
    private var normalColor:uint = 0x3A3A3A;      // Dark gray
    private var hoverColor:uint = 0x4A4A4A;       // Slightly lighter gray
    private var pressedColor:uint = 0x2A2A2A;     // Darker gray
    private var disabledColor:uint = 0x1A1A1A;    // Very dark gray
    private var borderColor:uint = 0x5A5A5A;      // Light gray border
    private var textColor:uint = 0xFFFFFF;        // White text
    private var disabledTextColor:uint = 0x666666; // Gray text when disabled

    public function SimpleButton(text:String, width:Number = 100, height:Number = 30) {
        buttonWidth = width;
        buttonHeight = height;

        createButton();
        setText(text);
        setupEventListeners();
    }

    private function createButton():void {
        // Create background sprite
        buttonBg = new Sprite();
        addChild(buttonBg);

        // Create text field
        buttonText = new TextField();
        buttonText.autoSize = TextFieldAutoSize.CENTER;
        buttonText.selectable = false;
        buttonText.mouseEnabled = false;

        // Set text format
        var format:TextFormat = new TextFormat();
        format.font = "Arial";
        format.size = 12;
        format.color = textColor;
        format.bold = true;
        buttonText.defaultTextFormat = format;

        addChild(buttonText);

        // Draw initial state
        drawButton(normalColor);
    }

    private function drawButton(bgColor:uint):void {
        var g:Graphics = buttonBg.graphics;
        g.clear();

        // Draw button background
        g.beginFill(bgColor);
        g.lineStyle(1, borderColor);
        g.drawRoundRect(0, 0, buttonWidth, buttonHeight, 4, 4);
        g.endFill();

        // Add slight inner highlight for 3D effect
        if (_enabled) {
            g.lineStyle(1, 0x6A6A6A, 0.5);
            g.moveTo(2, buttonHeight - 2);
            g.lineTo(2, 2);
            g.lineTo(buttonWidth - 2, 2);
        }
    }

    private function setText(text:String):void {
        buttonText.text = text;

        // Center the text
        buttonText.x = (buttonWidth - buttonText.width) / 2;
        buttonText.y = (buttonHeight - buttonText.height) / 2;
    }

    private function setupEventListeners():void {
        addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
        addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
        addEventListener(MouseEvent.MOUSE_DOWN, onMouseDown);
        addEventListener(MouseEvent.MOUSE_UP, onMouseUp);
        addEventListener(MouseEvent.CLICK, onClick);

        // Make it behave like a button
        buttonMode = true;
        useHandCursor = true;
    }

    // --- EVENT HANDLERS ---

    private function onMouseOver(e:MouseEvent):void {
        if (_enabled) {
            drawButton(hoverColor);
        }
    }

    private function onMouseOut(e:MouseEvent):void {
        if (_enabled) {
            drawButton(normalColor);
        }
    }

    private function onMouseDown(e:MouseEvent):void {
        if (_enabled) {
            drawButton(pressedColor);
        }
    }

    private function onMouseUp(e:MouseEvent):void {
        if (_enabled) {
            drawButton(hoverColor);
        }
    }

    private function onClick(e:MouseEvent):void {
        if (_enabled) {
            // Dispatch a custom event that parent can listen for
            dispatchEvent(new Event("buttonClicked"));
        }
    }

    // --- PUBLIC METHODS ---

    public function set enabled(value:Boolean):void {
        _enabled = value;

        if (_enabled) {
            drawButton(normalColor);
            buttonText.textColor = textColor;
            alpha = 1.0;
            mouseEnabled = true;
            useHandCursor = true;
        } else {
            drawButton(disabledColor);
            buttonText.textColor = disabledTextColor;
            alpha = 0.6;
            mouseEnabled = false;
            useHandCursor = false;
        }
    }

    public function get enabled():Boolean {
        return _enabled;
    }

    public function set text(value:String):void {
        setText(value);
    }

    public function get text():String {
        return buttonText.text;
    }

    // Custom color setters for theming
    public function setColors(normal:uint, hover:uint, pressed:uint, border:uint = 0x5A5A5A):void {
        normalColor = normal;
        hoverColor = hover;
        pressedColor = pressed;
        borderColor = border;

        if (_enabled) {
            drawButton(normalColor);
        }
    }

    public function setTextColor(color:uint):void {
        textColor = color;
        if (_enabled) {
            buttonText.textColor = color;
        }
    }
}
}