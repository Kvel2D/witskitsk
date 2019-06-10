
import haxegon.*;

import Tile;

using haxegon.MathExtensions;
using Lambda;

enum GameState {
    GameState_Normal;
    GameState_Interact;
    GameState_Lose;
}

enum InteractType {
    InteractType_None;
    InteractType_Turn;
    InteractType_Push;
    InteractType_Combat;
    InteractType_Steps;
}

enum ToolType {
    ToolType_None;
    ToolType_Sword;
    ToolType_Shield;
    ToolType_Turn;
    ToolType_Push;
}

enum Direction {
    Direction_None;
    Direction_Left;
    Direction_Right;
    Direction_Up;
    Direction_Down;
}

typedef Entity = {
    x: Int,
    y: Int,
    tools: Map<Direction, Array<ToolType>>,
    hp: Int,
    tile: Int,
};

typedef Tool = {
    x: Int,
    y: Int,
    types: Array<ToolType>,
};

@:publicFields
class Main {
// force unindent

static inline var SCREEN_WIDTH = 768;
static inline var SCREEN_HEIGHT = 768;
static inline var TILESIZE = 32;
static inline var WORLD_WIDTH = 6;
static inline var WORLD_HEIGHT = 6;
static inline var WORLD_SCALE = 4;
static inline var ANIMATION_TIMER_MAX = 20;
static inline var MAX_TOOLS = 4;
static inline var LOSE_TIMER_MAX = 2 * 60;

var game_state = GameState_Normal;
var current_interact = InteractType_None;
var interact_timer = 0;
var lose_timer = 0;

var interact_queue = new Array<InteractType>();
var interact_entity: Entity = null;
var interact_entity2: Entity = null;
var interact_entity_dx = 0;
var interact_entity_dy = 0;
var interact_direction = Direction_None;
var tool1_blocked = new Array<Int>();
var tool2_blocked = new Array<Int>();

var entities = new Array<Entity>();
var tools = new Array<Tool>();

var steps_pos = {x: 0, y: 0};
var level = 0;
var player: Entity = null;

function new() {
    Gfx.resizescreen(SCREEN_WIDTH, SCREEN_HEIGHT);
    Gfx.loadtiles('tiles', TILESIZE, TILESIZE);
    Gfx.createimage('unrotated_entity', TILESIZE * WORLD_SCALE, TILESIZE * WORLD_SCALE);

    restart();
}

function make_entity(x, y): Entity {
    var e = {
        x: x,
        y: y,
        tools: new Map<Direction, Array<ToolType>>(),
        hp: 1,
        tile: Tile.None,
    };
    for (d in Type.allEnums(Direction)) {
        e.tools[d] = new Array<ToolType>();
    }
    entities.push(e);

    return e;
}

function make_enemy(x, y, enemy_count): Entity {
    var e = make_entity(x, y);
    e.hp = 1;
    var tile_index = Random.int(0, level);
    if (Random.chance(50)) {
        // Scale towards higher indices often
        tile_index = Std.int(Math.min(9, Math.round(Math.pow(tile_index, 1.5))));
    }
    e.tile = Tile.Entity[tile_index];

    function scale(base: Float, factor: Float) {
        return Math.max(0.0, base + factor * level);
    }

    for (d in Type.allEnums(Direction)) {
        var tool_count = if (level == 0) {
            Random.pick_chance([
                {v: 0, c: 1.0},
                {v: 1, c: 1.0},
                ]);
        } else {
            Random.pick_chance([
                {v: 0, c: scale(1.0, -0.2)},
                {v: 1, c: scale(1.0, 0.2)},
                {v: 2, c: scale(0.75, 0.25)},
                {v: 3, c: scale(0.5, 0.3)},
                {v: 4, c: scale(0.25, 0.35)}
                ]);
        }

        // Reduce tool count slightly if many enemies
        var tool_count = Std.int(Math.round(tool_count * (3 / enemy_count)));
        var tool_type = Random.pick([ToolType_Sword, ToolType_Shield]);
        
        var sword_count = 0;
        e.tools[d] = [for (i in 0...tool_count) { if (sword_count < 2) Random.pick([ToolType_Sword, ToolType_Shield]); else ToolType_Shield;}];
    }

    return e;
}

function generate_level() {
    tools = new Array<Tool>();

    player.x = steps_pos.x;
    player.y = steps_pos.y;

    // Pick new steps pos far away from player, touching a wall
    while (Math.dst(steps_pos.x, steps_pos.y, player.x, player.y) < 4) {
        if (Random.chance(50)) {
            // Touch top/bottom wall
            steps_pos.x = Random.pick([0, 5]);
            steps_pos.y = Random.int(0, 5);
        } else {
            // Touch left/right wall
            steps_pos.x = Random.int(0, 5);
            steps_pos.y = Random.pick([0, 5]);
        }
    }

    var positions = new Array<Vec2i>();
    for (x in 0...WORLD_WIDTH) {
        for (y in 0...WORLD_WIDTH) {
            if ((x == steps_pos.x && y == steps_pos.y) || (x == player.x && y == player.y)) {
                continue;
            }
            positions.push({x: x, y: y});
        }
    }
    Random.shuffle(positions);

    for (e in entities) {
        if (e == player) {
            continue;
        }

        if (positions.length == 0) {
            break;
        }

        var pos = positions.pop();
        e.x = pos.x;
        e.y = pos.y;
    }

    var new_enemy_count = Random.int(3, 5);

    for (i in 0...new_enemy_count) {
        if (positions.length == 0) {
            break;
        }
        var pos = positions.pop();
        make_enemy(pos.x, pos.y, new_enemy_count);
    }

    var tool_count = Random.int(4, 6);

    for (i in 0...tool_count) {
        if (positions.length == 0) {
            break;
        }

        var pos = positions.pop();

        var k = 1;


        tools.push({
            x: pos.x,
            y: pos.y,
            types: if (level > 0) { 
                [for (i in 0...k) Random.pick_chance([
                    {v: ToolType_Sword, c: 8.0},
                    {v: ToolType_Shield, c: 4.0},
                    {v: ToolType_Push, c: 1.0},
                    {v: ToolType_Turn, c: 1.0}])];
            } else {
                [for (i in 0...k) Random.pick_chance([
                    {v: ToolType_Sword, c: 8.0},
                    {v: ToolType_Shield, c: 4.0}])];
            }
        });
    }

    function no_path(): Bool {
        var discovered = [for (x in 0...WORLD_WIDTH) [for (y in 0...WORLD_HEIGHT) false]];
        discovered[player.x][player.y] = true;
        var cardinals = [{x: -1, y: 0}, {x: 1, y: 0}, {x: 0, y: 1}, {x: 0, y: -1}];

        var free_map = [for (x in 0...WORLD_WIDTH) [for (y in 0...WORLD_HEIGHT) true]];

        free_map[steps_pos.x][steps_pos.y] = false;
        for (e in entities) {
            free_map[e.x][e.y] = false;
        }
        for (t in tools) {
            free_map[t.x][t.y] = false;
        }

        function dfs(x, y): Bool {
            if (x == steps_pos.y && y == steps_pos.y) {
                return true;
            }

            discovered[x][y] = true;

            for (dxdy in cardinals) {
                var new_x = x + dxdy.x;
                var new_y = y + dxdy.y;
                if (!out_of_bounds(new_x, new_y) && !discovered[new_x][new_y] && free_map[new_x][new_y]) {
                    if (dfs(new_x, new_y)) {
                        return true;
                    }
                }
            }

            return false;
        }

        return !dfs(player.x, player.y);
    }

    // Try to reposition enemies to remove path blocks
    // NOTE: with very high enemy counts just give up after a number of tries
    var tries = 0;
    while (no_path() && tries < 200) {
        tries++;

        if (Random.chance(50)) {
            // Move random enemy
            if (entities.length > 1 && positions.length >= 2) {
                var random_enemy = player;
                while (random_enemy == player) {
                    random_enemy = Random.pick(entities);
                }

                var temp = {x: random_enemy.x, y: random_enemy.y};
                var pos = positions.pop();
                random_enemy.x = pos.x;
                random_enemy.y = pos.y;

                if (temp.x != pos.x && temp.y != pos.y) {
                    positions.push(temp);
                }
            }
        } else {
            // Move random tool
            if (tools.length > 0 && positions.length >= 2) {
                var random_tool = Random.pick(tools);

                var temp = {x: random_tool.x, y: random_tool.y};
                var pos = positions.pop();
                random_tool.x = pos.x;
                random_tool.y = pos.y;

                if (temp.x != pos.x && temp.y != pos.y) {
                    positions.push(temp);
                }
            }
        }
    }
}

function restart() {
    level = 0;
    player = make_entity(0, 0);
    player.tile = Tile.Player;
    entities = [player];
    generate_level();
}

inline function screen_x(x) {
    return x * TILESIZE * WORLD_SCALE;
}
inline function screen_y(y) {
    return y * TILESIZE * WORLD_SCALE;
}
static inline function out_of_bounds(x, y) {
    return x < 0 || y < 0 || x >= WORLD_WIDTH || y >= WORLD_HEIGHT;
}

function draw_entity(e: Entity, no_offset = false, draw_tools = true, draw_entity = true, offset_x: Int = 0, offset_y: Int = 0, tools_offset: Int = 0, blocked_tools: Array<Int> = null, direction: Direction = null) {
    if (blocked_tools == null) {
        blocked_tools = [];
    } else {
        // trace(blocked_tools);
    }

    if (direction == null) {
        direction = Direction_None;
    }

    var saved_x = e.x;
    var saved_y = e.y;
    if (no_offset) {
        e.x = 0;
        e.y = 0;
    }

    var radius = TILESIZE * WORLD_SCALE / 2;

    var tool_x = 0;
    var tool_y = 0;

    if (draw_tools) {
        Gfx.rotation(0);
        tool_y = screen_y(e.y);
        for (i in 0...e.tools[Direction_Left].length) {
            var t = e.tools[Direction_Left][i];
            var tools_offset_x = 0;
            var tools_offset_y = 0;
            if (direction == Direction_Left && !contains(blocked_tools, i) && t == ToolType_Sword) {
                tools_offset_x = -tools_offset;
            }

            if (direction == Direction_Left && contains(blocked_tools, i)) {
                Gfx.imagealpha(tools_offset / 100);
            }

            Gfx.drawtile(screen_x(e.x) + offset_x + tools_offset_x, tool_y + offset_y + tools_offset_y, Tile.tools_attached(t));
            tool_y += 4 * WORLD_SCALE;

            Gfx.imagealpha(1);
        }

        Gfx.rotation(180);
        tool_y = screen_y(e.y);
        for (i in 0...e.tools[Direction_Right].length) {
            var t = e.tools[Direction_Right][i];
            var tools_offset_x = 0;
            var tools_offset_y = 0;
            if (direction == Direction_Right && !contains(blocked_tools, i) && t == ToolType_Sword) {
                tools_offset_x = tools_offset;
            }

            if (direction == Direction_Right && contains(blocked_tools, i)) {
                Gfx.imagealpha(tools_offset / 100);
            }

            Gfx.drawtile(screen_x(e.x) + radius * 2 + offset_x + tools_offset_x, tool_y + radius * 2 + offset_y + tools_offset_y, Tile.tools_attached(t));
            tool_y -= 4 * WORLD_SCALE;
            
            Gfx.imagealpha(1);
        }

        Gfx.rotation(90);
        tool_x = screen_x(e.x);
        for (i in 0...e.tools[Direction_Up].length) {
            var t = e.tools[Direction_Up][i];
            var tools_offset_x = 0;
            var tools_offset_y = 0;
            if (direction == Direction_Up && !contains(blocked_tools, i) && t == ToolType_Sword) {
                tools_offset_y = -tools_offset;
            }

            if (direction == Direction_Up && contains(blocked_tools, i)) {
                Gfx.imagealpha(tools_offset / 100);
            }

            Gfx.drawtile(tool_x + radius * 2 + offset_x + tools_offset_x, screen_y(e.y) + offset_y + tools_offset_y, Tile.tools_attached(t));

            tool_x -= 4 * WORLD_SCALE;

            Gfx.imagealpha(1);
        }

        Gfx.rotation(-90);
        tool_x = screen_x(e.x);
        for (i in 0...e.tools[Direction_Down].length) {
            var t = e.tools[Direction_Down][i];
            var tools_offset_x = 0;
            var tools_offset_y = 0;
            if (direction == Direction_Down && !contains(blocked_tools, i) && t == ToolType_Sword) {
                tools_offset_y = tools_offset;
            }

            if (direction == Direction_Down && contains(blocked_tools, i)) {
                Gfx.imagealpha(tools_offset / 100);
            }

            Gfx.drawtile(tool_x + offset_x + tools_offset_x, screen_y(e.y) + radius * 2 + offset_y + tools_offset_y, Tile.tools_attached(t));
            tool_x += 4 * WORLD_SCALE;

            Gfx.imagealpha(1);
        }
    }
    Gfx.rotation(0);

    if (draw_entity) {
        Gfx.rotation(0);
        Gfx.drawtile(screen_x(e.x) + offset_x, screen_y(e.y) + offset_y, e.tile);
        Gfx.imagealpha(1);

        // Text.display(screen_x(e.x) + radius - Text.width('${e.hp}') / 2 + offset_x, screen_y(e.y) + radius - Text.height('${e.hp}') / 2 + offset_y, '${e.hp}', Col.YELLOW);
    }

    if (no_offset) {
        e.x = saved_x;
        e.y = saved_y;
    }
}

function draw_tool(t: Tool) {
    var radius = TILESIZE * WORLD_SCALE / 2;

    var mini_tilesize = WORLD_SCALE * 8;
    
    var x = screen_x(t.x) + WORLD_SCALE * TILESIZE / 2 - mini_tilesize / 2;
    var y = screen_x(t.y) + WORLD_SCALE * TILESIZE / 2 - mini_tilesize / 2;

    switch (t.types.length) {
        case 1: {
            Gfx.drawtile(x, y, Tile.tools_free(t.types[0]));
        }
        case 2: {
            Gfx.drawtile(x - mini_tilesize / 2, y, Tile.tools_free(t.types[0]));
            Gfx.drawtile(x + mini_tilesize / 2, y, Tile.tools_free(t.types[1]));
        }
        case 3: {
            Gfx.drawtile(x - mini_tilesize / 2, y + mini_tilesize / 2, Tile.tools_free(t.types[0]));
            Gfx.drawtile(x + mini_tilesize / 2, y + mini_tilesize / 2, Tile.tools_free(t.types[1]));
            Gfx.drawtile(x, y - mini_tilesize / 2, Tile.tools_free(t.types[1]));
        }
        case 4: {
            Gfx.drawtile(x - mini_tilesize / 2, y - mini_tilesize / 2, Tile.tools_free(t.types[0]));
            Gfx.drawtile(x + mini_tilesize / 2, y - mini_tilesize / 2, Tile.tools_free(t.types[1]));
            Gfx.drawtile(x - mini_tilesize / 2, y + mini_tilesize / 2, Tile.tools_free(t.types[0]));
            Gfx.drawtile(x + mini_tilesize / 2, y + mini_tilesize / 2, Tile.tools_free(t.types[1]));
        }
        default: Gfx.drawtile(screen_x(t.x), screen_y(t.y), Tile.None);
    }
}

function print_entity(e: Entity) {
    trace(e);
    for (d in Type.allEnums(Direction)) {
        trace('$d = ${e.tools[d]}');
    }
}

function render() {
    Gfx.clearscreen(Col.BLACK);
    Gfx.scale(WORLD_SCALE);

    for (x in 0...WORLD_WIDTH) {
        for (y in 0...WORLD_HEIGHT) {
            var tile = if (x == steps_pos.x && y == steps_pos.y) Tile.Steps[level] else Tile.Floor;
            Gfx.drawtile(screen_x(x), screen_y(y), tile);
        }
    }

    for (t in tools) {
        draw_tool(t);
    }

    Gfx.scale(WORLD_SCALE);
    for (e in entities) {
        if ((e == interact_entity || e == interact_entity2) && current_interact != InteractType_None) {
            continue;
        }

        draw_entity(e);
    }
}

function entity_at(x: Int, y: Int): Entity {
    for (e in entities) {
        if (e.x == x && e.y == y) {
            return e;
        }
    }
    return null;
}

function tool_at(x: Int, y: Int): Tool {
    for (t in tools) {
        if (t.x == x && t.y == y) {
            return t;
        }
    }
    return null;
}

function get_direction(dx: Int, dy: Int): Direction {
    if (dx == 1 && dy == 0) {
        return Direction_Right;
    } else if (dx == -1 && dy == 0) {
        return Direction_Left;
    } else if (dx == 0 && dy == 1) {
        return Direction_Down;
    } else if (dx == 0 && dy == -1) {
        return Direction_Up;
    } else {
        return Direction_None;
    }
}

function get_dxdy(d: Direction): Vec2i {
    return switch (d) {
        case Direction_Right: {x: 1, y: 0};
        case Direction_Left: {x: -1, y: 0};
        case Direction_Up: {x: 0, y: -1};
        case Direction_Down: {x: 0, y: 1};
        case Direction_None: {x: 0, y: 0};
    }
}

function opposite(d: Direction): Direction {
    return switch (d) {
        case Direction_Right: Direction_Left;
        case Direction_Left: Direction_Right;
        case Direction_Up: Direction_Down;
        case Direction_Down: Direction_Up;
        case Direction_None: Direction_None;
    }
}

function contains(array: Array<Dynamic>, thing: Dynamic): Bool {
    return array.indexOf(thing) != -1;
}

function combat(e1: Entity, e2: Entity, direction1: Direction) {
    var direction2 = opposite(direction1);

    var tools1 = e1.tools[direction1];
    var tools2 = e2.tools[direction2];

    var e1_shields = new Array<Int>();
    var e1_swords = new Array<Int>();
    for (i in 0...tools1.length) {
        switch (tools1[i]) {
            case ToolType_Shield: e1_shields.push(i);
            case ToolType_Sword: e1_swords.push(i);
            default:
        } 
    }
    var e1_shields_length = e1_shields.length;
    var e1_swords_length = e1_swords.length;

    var e2_shields = new Array<Int>();
    var e2_swords = new Array<Int>();
    for (i in 0...tools2.length) {
        switch (tools2[i]) {
            case ToolType_Shield: e2_shields.push(i);
            case ToolType_Sword: e2_swords.push(i);
            default:
        } 
    }
    var e2_shields_length = e2_shields.length;
    var e2_swords_length = e2_swords.length;

    Random.shuffle(e1_shields);
    Random.shuffle(e1_swords);
    Random.shuffle(e2_shields);
    Random.shuffle(e2_swords);

    tool1_blocked = new Array<Int>();
    tool2_blocked = new Array<Int>();

    // e2 swords vs e1 shields
    if (e1_shields_length >= e2_swords_length) {
        for (i in 0...e2_swords_length) {
            tool2_blocked.push(e2_swords.pop());
            tool1_blocked.push(e1_shields.pop());
        }
    } else {
        for (i in 0...e1_shields_length) {
            tool2_blocked.push(e2_swords.pop());
            tool1_blocked.push(e1_shields.pop());
        }
    }

    // e1 swords attack e2 shields
    if (e2_shields_length >= e1_swords_length) {
        for (i in 0...e1_swords_length) {
            tool1_blocked.push(e1_swords.pop());
            tool2_blocked.push(e2_shields.pop());
        }
    } else {
        for (i in 0...e2_shields_length) {
            tool1_blocked.push(e1_swords.pop());
            tool2_blocked.push(e2_shields.pop());
        }
    }

    if (e1_swords_length > e2_shields_length || e2_swords_length > e1_shields_length || tool1_blocked.length > 0 || tool2_blocked.length > 0) {
        interact_entity = e1;
        interact_entity2 = e2;
        interact_queue.push(InteractType_Combat);
        interact_direction = direction1;
    }
}

function do_specials(doer: Entity, object: Entity, direction: Direction): Bool {
    var used_special = false;
    var used_push = false;

    while (true) {
        var used_tool: ToolType = ToolType_None;

        for (t in doer.tools[direction]) {
            if (t == ToolType_Turn) {
                interact_queue.push(InteractType_Turn);
                interact_entity = object;

                used_tool = t;
                break;
            } else if (t == ToolType_Push && !used_push) {
                var dxdy = get_dxdy(direction);
                var new_x = object.x + dxdy.x;
                var new_y = object.y + dxdy.y;

                if (!out_of_bounds(new_x, new_y)) {
                    var entity = entity_at(new_x, new_y);
                    
                    used_push = true;

                    if (entity == null) {
                        interact_entity_dx = dxdy.x;
                        interact_entity_dy = dxdy.y;

                        interact_queue.push(InteractType_Push);
                        interact_entity = object;
                        interact_direction = direction;


                        used_tool = t;
                        break;
                    } else {
                        combat(object, entity, direction);
                        used_tool = t;
                        break;
                    }
                }
            }
        }

        if (used_tool == ToolType_None) {
            break;
        } else {
            used_special = true;
            doer.tools[direction].remove(used_tool);
        }
    }

    return used_special;
}

function touch(player: Entity, entity: Entity, direction: Direction) {
    // Special entity on player
    var used_special = do_specials(entity, player, opposite(direction));

    // Special player on entity
    if (!used_special) {
        used_special = do_specials(player, entity, direction);
    }

    // Do player-entity combat if didn't use specials
    if (!used_special) {
        combat(player, entity, direction);
    }
}

function update_interact() {
    if (current_interact == InteractType_None) {
        if (interact_queue.length > 0) {
            current_interact = interact_queue.pop();
            interact_timer = ANIMATION_TIMER_MAX;

            if (current_interact == InteractType_Steps) {
                interact_timer = ANIMATION_TIMER_MAX * 2;
            }

            // Draw entity without rotation
            switch (current_interact) {
                case InteractType_Turn: {
                    Gfx.scale(WORLD_SCALE);
                    Gfx.drawtoimage('unrotated_entity');
                    Gfx.clearscreentransparent();
                    draw_entity(interact_entity, true, true, false);
                    Gfx.drawtoscreen();
                }
                default:
            }
        } else {
            interact_entity = null;
            interact_entity2 = null;

            if (player.hp <= 0) {
                game_state = GameState_Lose;
                lose_timer = LOSE_TIMER_MAX;
            } else {
                game_state = GameState_Normal;
            }
        }
    }

    render();

    var progress = interact_timer / ANIMATION_TIMER_MAX;
    
    switch (current_interact) {
        case InteractType_Turn: {
            Gfx.scale(1, 1, Gfx.CENTER, Gfx.CENTER);
            Gfx.rotation(90 * (1 - progress), Gfx.CENTER, Gfx.CENTER);
            var radius = TILESIZE * WORLD_SCALE;
            Gfx.drawimage(screen_x(interact_entity.x), screen_y(interact_entity.y), 'unrotated_entity');
            Gfx.rotation(0);

            Gfx.scale(WORLD_SCALE);
            draw_entity(interact_entity, false, false, true);
        }
        case InteractType_Push: {
            var offset = TILESIZE * WORLD_SCALE * (1 - progress);
            var offset_x = Math.round(offset * interact_entity_dx);
            var offset_y = Math.round(offset * interact_entity_dy);

            Gfx.scale(WORLD_SCALE);
            draw_entity(interact_entity, false, true, true, offset_x, offset_y);
        }
        case InteractType_Combat: {
            var offset = Math.round(0.5 * WORLD_SCALE * TILESIZE * Math.sin(Math.PI * progress));

            Gfx.scale(WORLD_SCALE);
            draw_entity(interact_entity, false, true, true, 0, 0, offset, tool1_blocked, interact_direction);
            draw_entity(interact_entity2, false, true, true, 0, 0, offset, tool2_blocked, opposite(interact_direction));
        }
        case InteractType_Steps: {
            Gfx.scale(WORLD_SCALE);
            Gfx.drawtile(screen_x(steps_pos.x), screen_y(steps_pos.y), Tile.Steps[level]);
            Gfx.imagealpha(Math.max(0, Math.round(progress / 2 * 4) / 4) - 0.4);
            Gfx.drawtile(screen_x(steps_pos.x), screen_y(steps_pos.y), Tile.Player);
            Gfx.imagealpha(1);
        }
        case InteractType_None:
    }

    interact_timer--;
    if (interact_timer <= 0) {
        switch (current_interact) {
            case InteractType_Turn: {
                var left = interact_entity.tools[Direction_Left].copy();
                var right = interact_entity.tools[Direction_Right].copy();
                var down = interact_entity.tools[Direction_Down].copy();
                var up = interact_entity.tools[Direction_Up].copy();

                interact_entity.tools[Direction_Left] = down;
                interact_entity.tools[Direction_Up] = left;
                interact_entity.tools[Direction_Right] = up;
                interact_entity.tools[Direction_Down] = right;
            } 
            case InteractType_Push: {
                interact_entity.x += interact_entity_dx;
                interact_entity.y += interact_entity_dy;

                var tool_there = tool_at(interact_entity.x, interact_entity.y);

                if (tool_there != null) {
                    while (interact_entity.tools[interact_direction].length < MAX_TOOLS && tool_there.types.length > 0) {
                        var t = tool_there.types.pop();
                        interact_entity.tools[interact_direction].push(t);
                    }
                    if (tool_there.types.length == 0) {
                        tools.remove(tool_there);
                    }
                }
            }
            case InteractType_Combat: {
                // Remove blocked tools
                var tools1 = interact_entity.tools[interact_direction];
                var removed1 = new Array<ToolType>();
                for (i in tool1_blocked) {
                    removed1.push(tools1[i]);
                }
                for (t in removed1) {
                    interact_entity.tools[interact_direction].remove(t);
                }

                var tools2 = interact_entity2.tools[opposite(interact_direction)];
                var removed2 = new Array<ToolType>();
                for (i in tool2_blocked) {
                    removed2.push(tools2[i]);
                }
                for (t in removed2) {
                    interact_entity2.tools[opposite(interact_direction)].remove(t);
                }

                // Remove used swords
                var swords1 = 0;
                var swords2 = 0;
                if (contains(interact_entity.tools[interact_direction], ToolType_Sword)) {
                    swords1++;
                }
                interact_entity.tools[interact_direction].remove(ToolType_Sword);
                if (contains(interact_entity2.tools[opposite(interact_direction)], ToolType_Sword)) {
                    swords2++;
                }
                interact_entity2.tools[opposite(interact_direction)].remove(ToolType_Sword);

                // Apply damage
                interact_entity.hp -= swords2;
                interact_entity2.hp -= swords1;

                if (interact_entity2.hp <= 0) {
                    var count = Random.int(1, 2);
                    var tool_type = Random.pick_chance([
                        {v: ToolType_Sword, c: 8.0},
                        {v: ToolType_Shield, c: 4.0},
                        ]);

                    tools.push({
                        x: interact_entity2.x,
                        y: interact_entity2.y,
                        types: [for (i in 0...count) tool_type],
                    });

                    entities.remove(interact_entity2);
                }
            }
            case InteractType_Steps: {
                level++;
                if (level > 8) {
                    level = 8;
                }
                // entities = [player];
                generate_level();
            }
            case InteractType_None:
        }

        current_interact = InteractType_None;
    }
}

function update_normal() {
    var turn_ended = false;

    var player_dx = 0;
    var player_dy = 0;
    var up = Input.delaypressed(Key.W, 4) || Input.delaypressed(Key.UP, 4);
    var down = Input.delaypressed(Key.S, 4) || Input.delaypressed(Key.DOWN, 4);
    var left = Input.delaypressed(Key.A, 4) || Input.delaypressed(Key.LEFT, 4);
    var right = Input.delaypressed(Key.D, 4) || Input.delaypressed(Key.RIGHT, 4);

    var count = 0;
    if (up) {
        count++;
    }
    if (down) {
        count++;
    }
    if (left) {
        count++;
    }
    if (right) {
        count++;
    }

    if (count == 1) {
        if (up) {
            player_dy = -1;
        } else if (down) {
            player_dy = 1;
        } else if (left) {
            player_dx = -1;
        } else if (right) {
            player_dx = 1;
        }

        turn_ended = true;
    }

    if (!turn_ended && Mouse.leftreleased()) {
        var x = Std.int(Mouse.x / TILESIZE / WORLD_SCALE);
        var y = Std.int(Mouse.y / TILESIZE / WORLD_SCALE);

        if (!out_of_bounds(x, y)) {
            var dst = Math.dst(player.x, player.y, x, y);
            if (dst <= 1 && dst != 0) {
                player_dx = x - player.x;
                player_dy = y - player.y;
                turn_ended = true;
            }
        }
    }


    //
    // End of turn
    //
    if (turn_ended) {
        if (player_dx != 0 || player_dy != 0) {
            var new_x = player.x + player_dx;
            var new_y = player.y + player_dy;

            if (!out_of_bounds(new_x, new_y)) {

                var tool = tool_at(new_x, new_y);
                var entity = entity_at(new_x, new_y);
                var direction = get_direction(player_dx, player_dy);

                if (entity != null) {
                    touch(player, entity, direction);

                    if (interact_queue.length > 0 && interact_entity != null) {
                        game_state = GameState_Interact;
                    }
                } else {
                    if (tool != null && player.tools[direction].length < 4) {
                        // Attach tool if there's a free slot
                        while (player.tools[direction].length < MAX_TOOLS && tool.types.length > 0) {
                            var t = tool.types.pop();
                            player.tools[direction].push(t);
                        }
                        if (tool.types.length == 0) {
                            tools.remove(tool);
                        }
                    }
                    
                    player.x = new_x;
                    player.y = new_y;
                }

                if (player.x == steps_pos.x && player.y == steps_pos.y) {
                    game_state = GameState_Interact;
                    interact_queue.push(InteractType_Steps);
                }
            }
        }
    }

    render();
}

function update_lose() {
    render();

    Gfx.drawtile(screen_x(player.x), screen_y(player.y), Tile.PlayerLose);

    Gfx.scale(1);
    Gfx.fillbox(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, Col.BLACK, Math.round((1 - lose_timer / LOSE_TIMER_MAX) * 4) / 4);

    lose_timer--;
    if (lose_timer <= 0) {
        game_state = GameState_Normal;
        restart();
    }
}

function update() {
    switch (game_state) {
        case GameState_Normal: update_normal();
        case GameState_Interact: update_interact();
        case GameState_Lose: update_lose();
    }

    if (Input.justpressed(Key.SPACE) || Mouse.rightreleased()) {
        game_state = GameState_Normal;
        restart();
    }
}

}
