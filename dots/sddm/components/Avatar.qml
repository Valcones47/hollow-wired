import QtQuick
import QtQuick.Controls

Canvas {
    id: avatar

    signal clicked
    signal clickedOutside

    property bool active: false
    property string source: ""
    property string shape: Config.avatarShape
    property int squareRadius: Config.avatarBorderRadius === 0 ? 1 : Config.avatarBorderRadius // min: 1
    property bool drawStroke: (active && Config.avatarActiveBorderSize > 0) || (!active && Config.avatarInactiveBorderSize > 0)
    property color strokeColor: active ? Config.avatarActiveBorderColor : Config.avatarInactiveBorderColor
    property int strokeSize: active ? Config.avatarActiveBorderSize : Config.avatarInactiveBorderSize
    property string tooltipText: ""
    property bool showTooltip: false

    onSourceChanged: {
        var src = resolveSource(source);
        if (src) avatar.loadImage(src);
        delayPaintTimer.running = true;
    }
    onImageLoaded: requestPaint()

    function resolveSource(s) {
        if (!s || s === "" || s.indexOf("user-default") !== -1 || s.indexOf("/faces/.face.icon") !== -1)
            return "../icons/default-avatar.png";
        return s;
    }

    Component.onCompleted: {
        var src = resolveSource(source);
        if (src) avatar.loadImage(src);
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset(); // Clear previous drawing
        ctx.beginPath();

        if (shape === "square") {
            // Squircle, actually
            const r = width * squareRadius / 100;
            ctx.moveTo(width - r, 0);
            ctx.arcTo(width, 0, width, height, r);
            ctx.arcTo(width, height, 0, height, r);
            ctx.arcTo(0, height, 0, 0, r);
            ctx.arcTo(0, 0, width, 0, r);
            ctx.closePath();
        } else {
            // Circle
            ctx.ellipse(0, 0, width, height);
        }
        ctx.clip();

        var actualSource = resolveSource(source);
        if (avatar.isImageLoaded(actualSource)) {
            ctx.drawImage(actualSource, 0, 0, width, height);
        } else {
            avatar.loadImage(actualSource);
            // Sem foto (usuário nunca escolheu uma, ou a pasta /home é 0700 e o
            // greeter não consegue ler o ~/.face): desenha uma silhueta em vez
            // de deixar um círculo vazio, que parecia um bug na tela de login.
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.07);
            ctx.fillRect(0, 0, width, height);
            ctx.fillStyle = Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.55);
            ctx.beginPath();
            ctx.ellipse(width * 0.34, height * 0.20, width * 0.32, height * 0.32);
            ctx.fill();
            ctx.beginPath();
            ctx.ellipse(width * 0.17, height * 0.60, width * 0.66, height * 0.62);
            ctx.fill();
        }

        // Border
        if (drawStroke) {
            ctx.strokeStyle = strokeColor;
            ctx.lineWidth = strokeSize;
            ctx.stroke();
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor

        function isCursorInsideAvatar() {
            if (!mouseArea.containsMouse)
                return false;
            if (avatar.shape === "square")
                return true;

            // Ellipse center and radius
            const centerX = width / 2;
            const centerY = height / 2;
            const radiusX = centerX;
            const radiusY = centerY;

            // Distance from center
            const dx = (mouseArea.mouseX - centerX) / radiusX;
            const dy = (mouseArea.mouseY - centerY) / radiusY;

            // Check if pointer is inside the ellipse
            return (dx * dx + dy * dy) <= 1.0;
        }

        onReleased: mouse => {
            const isInside = isCursorInsideAvatar();
            if (isInside) {
                avatar.clicked();
            } else {
                avatar.clickedOutside();
            }
            mouse.accepted = isInside;
        }

        function updateHover() {
            if (isCursorInsideAvatar()) {
                cursorShape = Qt.PointingHandCursor;
            } else {
                cursorShape = Qt.ArrowCursor;
            }
        }

        onMouseXChanged: updateHover()
        onMouseYChanged: updateHover()

        ToolTip {
            parent: mouseArea
            enabled: Config.tooltipsEnable && !Config.tooltipsDisableUser
            visible: enabled && avatar.showTooltip || (enabled && mouseArea.isCursorInsideAvatar() && avatar.tooltipText !== "")
            delay: 300
            contentItem: Text {
                font.family: Config.tooltipsFontFamily
                font.pixelSize: Config.tooltipsFontSize
                text: avatar.tooltipText
                color: Config.tooltipsContentColor
            }
            background: Rectangle {
                color: Config.tooltipsBackgroundColor
                opacity: Config.tooltipsBackgroundOpacity
                border.width: 0
                radius: Config.tooltipsBorderRadius
            }
        }
    }

    // FIX: paint() not affect event if source is not empty in initialization
    Timer {
        id: delayPaintTimer
        repeat: false
        interval: 150
        onTriggered: avatar.requestPaint()
        running: true
    }
}
