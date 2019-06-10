
import Main;

@:publicFields
class Tile {
    static inline var tileset_width = 10;
    static inline function at(x: Int, y: Int): Int {
        return y * tileset_width + x;
    }

    static inline var None = at(0, 0); // for bugged/invisible things
    static inline var Floor = at(0, 2);
    static inline var Player = at(1, 0);
    static inline var PlayerLose = at(2, 0);
    static var Entity = [for (i in 0...10) at(i, 1)];
    static var Steps = [for (i in 1...10) at(i, 2)];

    static function tools_free(tool: ToolType): Int {
        return switch (tool) {
            case ToolType_Sword: at(0, 3);
            case ToolType_Shield: at(1, 3);
            case ToolType_Turn: at(2, 3);
            case ToolType_Push: at(3, 3);
            case ToolType_None: Tile.None;
        }
    }

    static function tools_attached(tool: ToolType): Int {
        return switch (tool) {
            case ToolType_Sword: at(0, 4);
            case ToolType_Shield: at(1, 4);
            case ToolType_Turn: at(2, 4);
            case ToolType_Push: at(3, 4);
            case ToolType_None: Tile.None;
        }
    }

}