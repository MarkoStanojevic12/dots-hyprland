pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var messageData: {}
    property bool done: true
    property bool forceDisableChunkSplitting: false
    // Optional overrides. Left unset, links open in the system handler and
    // keep whatever colour the style gives them.
    property var linkHandler: null
    // Ctrl+click on a link. onLinkActivated carries no modifier state, so it is detected on the
    // press below and routed here instead.
    property var linkAltHandler: null
    property color linkColor: "transparent"

    // Inline `code` gets a filled background so short identifiers stand out
    // mid-sentence, the way they do in an editor.
    property bool highlightInlineCode: true
    // Opaque surface roles rather than the colLayer* ones: those carry an
    // alpha channel for the panel's transparency, and CSS here can't express
    // it — stripping the alpha turns a faint tint into a solid slab.
    // One step above the message's own surface reads as a chip without
    // glaring, and full-strength onSurface makes the code brighter than the
    // prose around it.
    property color inlineCodeBackground: Appearance.m3colors.m3surfaceContainerHighest
    property color inlineCodeColor: Appearance.m3colors.m3onSurface
    // Overridable so a tab can set its own reading size without moving the
    // shell's type scale out from under everything else.
    property int bodyFontSize: Appearance.font.pixelSize.small
    // Monospace sits optically larger than the reading face at a matched
    // size, so it's nudged down to keep the line rhythm even.
    property int inlineCodeFontSize: Math.round(root.bodyFontSize * 0.94)

    property list<string> renderedLatexHashes: []
    property string renderedSegmentContent: ""
    property string shownText: ""
    property bool fadeChunkSplitting: !forceDisableChunkSplitting && !editing && !/\n\|/.test(shownText) && Config.options.sidebar.ai.textFadeIn

    Layout.fillWidth: true

    Timer {
        id: renderTimer
        interval: 1000
        repeat: false
        onTriggered: {
            renderLatex()
            for (const hash of renderedLatexHashes) {
                handleRenderedLatex(hash, true);
            }
        }
    }

    function renderLatex() {
        // Regex for $...$, $$...$$, \[...\]
        // Note: This is a simple approach and may need refinement for edge cases
        let regex = /(\$\$([\s\S]+?)\$\$)|(\$([^\$]+?)\$)|(\\\[((?:.|\n)+?)\\\])|(\\\(([\s\S]+?)\\\))/g;
        let match;
        while ((match = regex.exec(segmentContent)) !== null) {
            let expression = match[1] || match[2] || match[3] || match[4] || match[5] || match[6] || match[7] || match[8];
            if (expression) {
                Qt.callLater(() => {
                    const [renderHash, isNew] = LatexRenderer.requestRender(expression.trim());
                    if (!renderedLatexHashes.includes(renderHash)) {
                        renderedLatexHashes.push(renderHash);
                    }
                });
            }
        }
    }

    function handleRenderedLatex(hash, force = false) {
        if (renderedLatexHashes.includes(hash) || force) {
            const imagePath = LatexRenderer.renderedImagePaths[hash];
            const markdownImage = `![latex](${imagePath})`;

            const expression = LatexRenderer.processedExpressions[hash];
            renderedSegmentContent = renderedSegmentContent.replace(expression, markdownImage);
        }
    }

    onDoneChanged: {
        renderTimer.restart();
    }
    onEditingChanged: {
        if (!editing) {
            renderLatex()
        } else {
            // console.log("Editing mode enabled", segmentContent)
            root.shownText = segmentContent
        }
    }

    onSegmentContentChanged: {
        // console.log("Segment content changed: " + segmentContent);
        renderedSegmentContent = segmentContent;
        if (!root.editing && segmentContent) {
            root.renderLatex();
        }
    }

    onRenderedSegmentContentChanged: {
        // console.log("Rendered segment content changed: " + renderedSegmentContent);
        if (renderedSegmentContent) {
            root.shownText = renderedSegmentContent;
        }
    }

    // When something finishes rendering
    // 1. Check if the hash is in the list
    // 2. If it is, replace the expression with the image path
    Connections {
        target: LatexRenderer
        function onRenderFinished(hash, imagePath) {
            const expression = LatexRenderer.processedExpressions[hash];
            // console.log("Render finished: " + hash + " " + expression);
            handleRenderedLatex(hash);
        }
    }

    spacing: 0
    Repeater {
        id: textLinesRepeater
        property list<real> textLineOpacities: []
        model: ScriptModel {
            // Split by either double newlines or single newlines in a list
            values: root.fadeChunkSplitting ? root.shownText.split(/\n\n(?= {0,2})|\n(?= {0,2}[-\*])/g).filter(line => line.trim() !== "") : [root.shownText]
            onValuesChanged: {
                while (textLinesRepeater.textLineOpacities.length < values.length) {
                    textLinesRepeater.textLineOpacities.push(root.messageData.done ? 1 : 0);
                }
            }
        }
        delegate: TextArea {
            id: textArea
            required property int index
            required property string modelData

            // Fade in animation
            visible: opacity > 0
            opacity: fadeChunkSplitting ? (textLinesRepeater.textLineOpacities[index] ?? (root.messageData.done ? 1 : 0)) : 1
            Connections {
                target: root.messageData
                function onDoneChanged() {
                    if (root.messageData.done) {
                        textLinesRepeater.textLineOpacities[textArea.index] = 1
                    }
                }
            }
            Connections {
                target: textLinesRepeater.model
                function onValuesChanged() {
                    if (textLinesRepeater.model.values.length > textArea.index + 1) {
                        textLinesRepeater.textLineOpacities[textArea.index] = 1
                    }
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Layout.fillWidth: true
            readOnly: !editing
            selectByMouse: enableMouseSelection || editing
            renderType: Text.NativeRendering
            font.family: Appearance.font.family.reading
            font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
            font.pixelSize: root.bodyFontSize
            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            wrapMode: TextEdit.Wrap
            color: root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
            textFormat: renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
            // Left raw while editing, so what's edited is what was written.
            text: (root.renderMarkdown && root.highlightInlineCode && !root.editing)
                ? StringUtils.styleInlineCode(modelData,
                    StringUtils.cssColor(root.inlineCodeBackground),
                    StringUtils.cssColor(root.inlineCodeColor),
                    Appearance.font.family.monospace,
                    root.inlineCodeFontSize)
                : modelData

            onTextChanged: {
                if (!root.editing) return
                segmentContent = text
            }

            onLinkActivated: (link) => {
                if (root.linkHandler) {
                    root.linkHandler(link)
                    return
                }
                Qt.openUrlExternally(link)
                GlobalStates.sidebarLeftOpen = false
            }

            Binding { // Only takes effect when a colour was actually asked for
                target: textArea
                property: "palette.link"
                value: root.linkColor
                when: root.linkColor.a > 0
            }

            MouseArea { // Pointing hand for links
                anchors.fill: parent
                acceptedButtons: Qt.NoButton // Only for hover
                hoverEnabled: true
                cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : 
                    (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
            }

            MouseArea { // Ctrl+click on a link, without disturbing anything else
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                // Declining the press hands it straight back to the TextArea, so plain clicks,
                // text selection and normal link activation all behave exactly as before.
                onPressed: mouse => {
                    const onLink = textArea.hoveredLink !== "";
                    const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                    if (!onLink || !ctrl || !root.linkAltHandler) {
                        mouse.accepted = false;
                        return;
                    }
                    root.linkAltHandler(textArea.hoveredLink);
                }
            }

            // Rectangle {
            //     anchors.fill: parent
            //     color: "#22786378"
            //     border.width: 1
            //     border.color: "#7E7E7E"
            // }
        }
    }
}
