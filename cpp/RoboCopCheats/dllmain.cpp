// RoboCop Cheats GUI tab (UE4SS C++ mod).
//
// This DLL only draws the "RoboCop Cheats" tab in the UE4SS GUI window and queues clicks.
// All game interaction stays in Scripts/main.lua (the code path verified in game).
//
// Bridge: when the Lua mod of the same name starts, we register these globals in its state:
//   RC_UI_Clear()                       Lua is (re)starting; forget the lists
//   RC_UI_AddWeapon(display, asset)     add a weapon button
//   RC_UI_AddAmmo(display, asset)       add an ammo button
//   RC_UI_AddBoard(display, row)        add an upgrade board button (DT_WeaponUpgradeBoards row)
//   RC_UI_Pop() -> string|nil           next queued request: "give <asset>" / "ammo <asset> <amount>" /
//                                       "chip <arms mask> <percent> <look 1-4>" / "board <row>" /
//                                       "skill <amount>" / "skillclear"
//   RC_UI_Status(msg)                   status line shown at the top of the tab
//   RC_UI_SetDlcWeapon(asset)           current DLC starting weapon ("default" = game's own)
//                                       (combo sends "dlcweapon <asset|default>")
// The GUI runs on UE4SS's render thread and Lua polls on the game thread, so all shared
// state is behind one mutex.

#include <Mod/CppUserModBase.hpp>
#include <UE4SSProgram.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <imgui.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <deque>
#include <format>
#include <mutex>
#include <string>
#include <vector>

using namespace RC;

namespace
{
    struct WeaponEntry
    {
        std::string display;
        std::string asset;
    };

    std::mutex g_mutex;
    std::vector<WeaponEntry> g_weapons;
    std::vector<WeaponEntry> g_ammo;   // same shape: display label + asset name
    std::vector<WeaponEntry> g_boards; // display label + DataTable row name
    std::deque<std::string> g_requests;
    std::string g_dlc_weapon = "default"; // asset name, or "default"
    std::string g_status = "Waiting for the RoboCopCheats Lua script to start...";
    bool g_lua_connected = false;

    constexpr size_t MaxQueuedRequests = 16;

    void push_request(std::string request)
    {
        std::lock_guard lock{g_mutex};
        if (g_requests.size() < MaxQueuedRequests) g_requests.push_back(std::move(request));
    }

    // Lua -> C++ ---------------------------------------------------------------------------
    // LuaMadeSimple's get_string() pops stack index 1, so successive calls read args in order.
    // The returned view points into Lua memory; copy it immediately.

    int rc_lua_clear(const LuaMadeSimple::Lua&)
    {
        std::lock_guard lock{g_mutex};
        g_weapons.clear();
        g_ammo.clear();
        g_boards.clear();
        g_requests.clear();
        g_lua_connected = true;
        g_status = "Ready. Load into a level, then click a weapon.";
        return 0;
    }

    int rc_lua_add_weapon(const LuaMadeSimple::Lua& lua)
    {
        if (!lua.is_string()) return 0;
        std::string display{lua.get_string()};
        if (!lua.is_string()) return 0;
        std::string asset{lua.get_string()};
        std::lock_guard lock{g_mutex};
        g_weapons.push_back({std::move(display), std::move(asset)});
        return 0;
    }

    int rc_lua_add_ammo(const LuaMadeSimple::Lua& lua)
    {
        if (!lua.is_string()) return 0;
        std::string display{lua.get_string()};
        if (!lua.is_string()) return 0;
        std::string asset{lua.get_string()};
        std::lock_guard lock{g_mutex};
        g_ammo.push_back({std::move(display), std::move(asset)});
        return 0;
    }

    int rc_lua_add_board(const LuaMadeSimple::Lua& lua)
    {
        if (!lua.is_string()) return 0;
        std::string display{lua.get_string()};
        if (!lua.is_string()) return 0;
        std::string row{lua.get_string()};
        std::lock_guard lock{g_mutex};
        g_boards.push_back({std::move(display), std::move(row)});
        return 0;
    }

    int rc_lua_pop(const LuaMadeSimple::Lua& lua)
    {
        std::string request;
        {
            std::lock_guard lock{g_mutex};
            if (!g_requests.empty())
            {
                request = std::move(g_requests.front());
                g_requests.pop_front();
            }
        }
        if (request.empty()) lua.set_nil();
        else lua.set_string(request);
        return 1;
    }

    int rc_lua_set_dlc_weapon(const LuaMadeSimple::Lua& lua)
    {
        if (!lua.is_string()) return 0;
        std::string asset{lua.get_string()};
        std::lock_guard lock{g_mutex};
        g_dlc_weapon = std::move(asset);
        return 0;
    }

    int rc_lua_status(const LuaMadeSimple::Lua& lua)
    {
        if (!lua.is_string()) return 0;
        std::string msg{lua.get_string()};
        std::lock_guard lock{g_mutex};
        g_status = std::move(msg);
        return 0;
    }

    // GUI ----------------------------------------------------------------------------------

    bool contains_ci(const std::string& haystack, const char* needle)
    {
        if (!needle || !*needle) return true;
        std::string h = haystack, n = needle;
        auto lower = [](std::string& s) {
            std::ranges::transform(s, s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        };
        lower(h);
        lower(n);
        return h.find(n) != std::string::npos;
    }

    // This DLL has its own copy of ImGui (nothing ImGui is imported from UE4SS.dll), so its
    // current-context pointer must be pointed at UE4SS's context before any ImGui call.
    // UE4SS_ENABLE_IMGUI() in on_ui_init() is not enough: UE4SS only fires on_ui_init at
    // initial startup, NOT after "Restart All Mods" / hot reload (start_cpp_mods() is called
    // with IsInitialStartup::No). The reloaded DLL then drew with a null context and crashed
    // in ImGui::TextWrapped (access violation reading 0x1440; crash dumps 2026-11-13).
    // Tab callbacks always run on UE4SS's render thread with its context current, so binding
    // here is always correct and costs two pointer compares per frame.
    bool bind_ue4ss_imgui()
    {
        ImGuiContext* ctx = UE4SSProgram::get_current_imgui_context();
        if (!ctx) return false;
        if (ImGui::GetCurrentContext() != ctx)
        {
            ImGuiMemAllocFunc alloc_func{};
            ImGuiMemFreeFunc free_func{};
            void* user_data{};
            UE4SSProgram::get_current_imgui_allocator_functions(&alloc_func, &free_func, &user_data);
            ImGui::SetAllocatorFunctions(alloc_func, free_func, user_data);
            ImGui::SetCurrentContext(ctx);
        }
        return true;
    }

    // Weapon the Deluxe/DLC edition hands out at level start (OCP Combat Shotgun by default).
    // The OCP Combat Shotgun itself is left out of the list: "Game default" is that weapon.
    constexpr const char* DlcDefaultAsset = "WP_MossbergBullpup";

    void draw_dlc_weapon_picker(const std::vector<WeaponEntry>& weapons, const std::string& current)
    {
        std::string preview = "Game default (OCP Combat Shotgun)";
        for (const auto& w : weapons)
        {
            if (w.asset == current) preview = w.display;
        }
        ImGui::SetNextItemWidth(260.0f);
        if (ImGui::BeginCombo("DLC starting weapon", preview.c_str()))
        {
            if (ImGui::Selectable("Game default (OCP Combat Shotgun)", current == "default")) push_request("dlcweapon default");
            for (const auto& w : weapons)
            {
                if (w.asset == DlcDefaultAsset) continue;
                ImGui::PushID(w.asset.c_str());
                if (ImGui::Selectable(w.display.c_str(), w.asset == current)) push_request("dlcweapon " + w.asset);
                ImGui::PopID();
            }
            ImGui::EndCombo();
        }
        if (ImGui::IsItemHovered())
        {
            ImGui::SetTooltip("With the Deluxe edition, levels start you with the OCP Combat Shotgun.\n"
                              "Pick another weapon to get that instead. Saved; applies from the next level start.");
        }
    }

    void draw_weapons_page(const std::vector<WeaponEntry>& weapons, const std::vector<WeaponEntry>& ammo, const std::string& dlc_weapon)
    {
        static char filter[64]{};
        static int ammo_amount = 200;

        draw_dlc_weapon_picker(weapons, dlc_weapon);
        ImGui::Separator();

        ImGui::SetNextItemWidth(220.0f);
        ImGui::InputTextWithHint("##filter", "Filter weapons / ammo...", filter, sizeof(filter));
        ImGui::SameLine();
        if (ImGui::Button("Clear")) filter[0] = '\0';

        if (!ImGui::BeginTable("rc_table", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_BordersInnerV)) return;
        ImGui::TableSetupColumn("Weapons (comes with ammo)");
        ImGui::TableSetupColumn("Ammo");
        ImGui::TableHeadersRow();
        ImGui::TableNextRow();

        // Weapons
        ImGui::TableSetColumnIndex(0);
        if (ImGui::BeginChild("weapons", ImVec2(0, 0)))
        {
            for (const auto& w : weapons)
            {
                if (!contains_ci(w.display, filter) && !contains_ci(w.asset, filter)) continue;
                ImGui::PushID(w.asset.c_str());
                if (ImGui::Button(w.display.c_str(), ImVec2(-FLT_MIN, 0))) push_request("give " + w.asset);
                if (ImGui::IsItemHovered()) ImGui::SetTooltip("%s", w.asset.c_str());
                ImGui::PopID();
            }
        }
        ImGui::EndChild();

        // Ammo
        ImGui::TableSetColumnIndex(1);
        if (ImGui::BeginChild("ammo", ImVec2(0, 0)))
        {
            ImGui::SetNextItemWidth(120.0f);
            if (ImGui::InputInt("Amount", &ammo_amount, 10, 100)) ammo_amount = std::clamp(ammo_amount, 1, 9999);
            for (const auto& a : ammo)
            {
                if (!contains_ci(a.display, filter) && !contains_ci(a.asset, filter)) continue;
                ImGui::PushID(a.asset.c_str());
                if (ImGui::Button(a.display.c_str(), ImVec2(-FLT_MIN, 0))) push_request(std::format("ammo {} {}", a.asset, ammo_amount));
                if (ImGui::IsItemHovered()) ImGui::SetTooltip("%s", a.asset.c_str());
                ImGui::PopID();
            }
        }
        ImGui::EndChild();

        ImGui::EndTable();
    }

    // Chip arms. Bit values must match ARM_* in main.lua, which turns a set of arms into
    // the game's (EChipConnectionType, rotation) pair.
    enum ChipArm : int
    {
        ArmUp = 1,
        ArmRight = 2,
        ArmDown = 4,
        ArmLeft = 8,
        ArmAll = ArmUp | ArmRight | ArmDown | ArmLeft,
    };

    // A clickable "+": the centre is the chip body, each arm toggles on/off.
    void draw_chip_editor(int& arms)
    {
        constexpr float cell = 36.0f;
        struct ArmDef
        {
            int bit;
            int col, row;
            const char* id;
            const char* name;
        };
        constexpr ArmDef defs[] = {
            {ArmUp, 1, 0, "##arm_up", "Up"},
            {ArmRight, 2, 1, "##arm_right", "Right"},
            {ArmDown, 1, 2, "##arm_down", "Down"},
            {ArmLeft, 0, 1, "##arm_left", "Left"},
        };

        ImDrawList* dl = ImGui::GetWindowDrawList();
        const ImVec2 origin = ImGui::GetCursorScreenPos();
        const ImU32 on_col = ImGui::GetColorU32(ImGuiCol_ButtonActive);
        const ImU32 off_col = ImGui::GetColorU32(ImGuiCol_FrameBg);
        const ImU32 hover_col = ImGui::GetColorU32(ImGuiCol_Text);
        const float bar = cell * 0.42f; // arm thickness
        const float inset = (cell - bar) * 0.5f;

        for (const auto& d : defs)
        {
            const ImVec2 cell_min{origin.x + d.col * cell, origin.y + d.row * cell};
            ImGui::SetCursorScreenPos(cell_min);
            if (ImGui::InvisibleButton(d.id, ImVec2(cell, cell))) arms ^= d.bit;
            const bool hovered = ImGui::IsItemHovered();
            if (hovered) ImGui::SetTooltip("%s arm: %s (click to toggle)", d.name, (arms & d.bit) ? "on" : "off");

            // Bar across this cell, touching the chip body, so arms look attached.
            ImVec2 a = cell_min;
            ImVec2 b{cell_min.x + cell, cell_min.y + cell};
            if (d.col == 1)
            {
                a.x += inset; // vertical arm
                b.x -= inset;
            }
            else
            {
                a.y += inset; // horizontal arm
                b.y -= inset;
            }
            dl->AddRectFilled(a, b, (arms & d.bit) ? on_col : off_col, 3.0f);
            if (hovered) dl->AddRect(a, b, hover_col, 3.0f);
        }

        // Chip body
        const float pad = cell * 0.08f;
        dl->AddRectFilled(ImVec2(origin.x + cell + pad, origin.y + cell + pad),
                          ImVec2(origin.x + 2 * cell - pad, origin.y + 2 * cell - pad),
                          ImGui::GetColorU32(ImGuiCol_Button),
                          4.0f);

        // Reserve the 3x3 area so the layout continues below it.
        ImGui::SetCursorScreenPos(origin);
        ImGui::Dummy(ImVec2(3 * cell, 3 * cell));
    }

    std::string arms_text(int arms)
    {
        constexpr std::pair<int, const char*> names[] = {{ArmUp, "Up"}, {ArmRight, "Right"}, {ArmDown, "Down"}, {ArmLeft, "Left"}};
        std::string s;
        for (const auto& [bit, name] : names)
        {
            if (!(arms & bit)) continue;
            if (!s.empty()) s += " + ";
            s += name;
        }
        return s.empty() ? "none" : s;
    }

    // The game shows a chip's value as Boost * 1.5, rounded half up (read from the chip
    // widgets in game, 2026-11-13). Must match CHIP_DISPLAY_MULT in main.lua, which does the
    // actual percent -> boost conversion; this copy only drives the preview.
    constexpr double ChipDisplayMultiplier = 1.5;

    int chip_boost_to_percent(int boost)
    {
        return static_cast<int>(std::floor(boost * ChipDisplayMultiplier + 0.5));
    }

    int chip_closest_percent(int wanted)
    {
        const int guess = static_cast<int>(std::floor(wanted / ChipDisplayMultiplier + 0.5));
        int best = std::max(1, guess - 1);
        for (int b = best; b <= guess + 1; ++b)
        {
            if (std::abs(chip_boost_to_percent(b) - wanted) < std::abs(chip_boost_to_percent(best) - wanted)) best = b;
        }
        return chip_boost_to_percent(best);
    }

    void draw_chips_page(const std::vector<WeaponEntry>& boards)
    {
        static int arms = ArmUp | ArmDown;
        static int percent = 30;
        static int look = 0; // combo index; sent as 1..4 (game ChipTier 0..3)
        constexpr const char* looks[] = {"Normal", "Style 2 (ring)", "Style 3", "Style 4"};

        ImGui::SeparatorText("Chip");
        ImGui::BeginGroup();
        draw_chip_editor(arms);
        ImGui::EndGroup();
        ImGui::SameLine(0.0f, 20.0f);
        ImGui::BeginGroup();
        ImGui::TextUnformatted("Click the arms to choose which sides connect.");
        ImGui::Text("Arms: %s", arms_text(arms).c_str());
        if (ImGui::SmallButton("All")) arms = ArmAll;
        ImGui::SameLine();
        if (ImGui::SmallButton("None")) arms = 0;
        ImGui::SetNextItemWidth(120.0f);
        if (ImGui::InputInt("Value %", &percent, 1, 5)) percent = std::clamp(percent, 2, 999);
        if (ImGui::IsItemHovered()) ImGui::SetTooltip("The %% shown on the chip in game. Chips the game drops go up to 45%%; higher values work but are beyond normal play.");
        const int shown = chip_closest_percent(percent);
        if (shown == percent) ImGui::TextDisabled("Shows in game as %d%%", shown);
        else ImGui::TextDisabled("Shows in game as %d%% (closest the game allows)", shown);
        ImGui::SetNextItemWidth(120.0f);
        ImGui::Combo("Look", &look, looks, IM_ARRAYSIZE(looks));
        if (ImGui::IsItemHovered()) ImGui::SetTooltip("Only changes how the chip looks. Normal matches the chips you find in game.");
        ImGui::BeginDisabled(arms == 0);
        if (ImGui::Button("Give chip", ImVec2(120.0f, 0))) push_request(std::format("chip {} {} {}", arms, percent, look + 1));
        ImGui::EndDisabled();
        ImGui::EndGroup();

        ImGui::SeparatorText("Upgrade boards");
        if (boards.empty())
        {
            ImGui::TextWrapped("The board list appears once you're in a level.");
            return;
        }
        if (ImGui::BeginChild("boards", ImVec2(0, 0)))
        {
            for (const auto& b : boards)
            {
                ImGui::PushID(b.asset.c_str());
                if (ImGui::Button(b.display.c_str(), ImVec2(-FLT_MIN, 0))) push_request("board " + b.asset);
                ImGui::PopID();
            }
        }
        ImGui::EndChild();
    }

    // Max per click; must match MAX_SKILL_POINTS_PER_GIVE in main.lua (Lua clamps too).
    constexpr int MaxSkillPointsPerGive = 100;

    void draw_skills_page()
    {
        static int amount = 1;

        ImGui::SeparatorText("Skill points");
        ImGui::TextWrapped("Adds unspent skill points. Spend them on the Skills screen as usual.");
        ImGui::SetNextItemWidth(120.0f);
        if (ImGui::InputInt("Amount##skill", &amount, 1, 5)) amount = std::clamp(amount, 1, MaxSkillPointsPerGive);
        if (ImGui::Button("Add skill points", ImVec2(160.0f, 0))) push_request(std::format("skill {}", amount));
        ImGui::TextDisabled("The status line above shows how many you now have unspent.");
        ImGui::Spacing();
        if (ImGui::Button("Remove unspent points", ImVec2(160.0f, 0))) push_request("skillclear");
        if (ImGui::IsItemHovered())
        {
            ImGui::SetTooltip("Sets your unspent skill points to 0. Handy once every skill is maxed:\n"
                              "leveling up keeps giving points you can't spend, and the game keeps reminding you.");
        }
    }

    void draw_cheats_tab()
    {
        if (!bind_ue4ss_imgui()) return;

        std::vector<WeaponEntry> weapons;
        std::vector<WeaponEntry> ammo;
        std::vector<WeaponEntry> boards;
        std::string status;
        std::string dlc_weapon;
        bool connected;
        {
            std::lock_guard lock{g_mutex};
            weapons = g_weapons;
            ammo = g_ammo;
            boards = g_boards;
            status = g_status;
            dlc_weapon = g_dlc_weapon;
            connected = g_lua_connected;
        }

        ImGui::TextWrapped("%s", status.c_str());
        if (!connected)
        {
            ImGui::TextWrapped("Make sure Mods/RoboCopCheats/Scripts/main.lua exists and RoboCopCheats is enabled in mods.txt.");
            return;
        }
        ImGui::Separator();

        if (!ImGui::BeginTabBar("rc_pages")) return;
        if (ImGui::BeginTabItem("Weapons & Ammo"))
        {
            draw_weapons_page(weapons, ammo, dlc_weapon);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("Chips & Boards"))
        {
            draw_chips_page(boards);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("Skills"))
        {
            draw_skills_page();
            ImGui::EndTabItem();
        }
        ImGui::EndTabBar();
    }
} // namespace

class RoboCopCheatsMod : public CppUserModBase
{
  public:
    RoboCopCheatsMod() : CppUserModBase()
    {
        ModName = STR("RoboCopCheats");
        ModVersion = STR("1.0");
        ModDescription = STR("Cheats tab for RoboCop: Rogue City: weapons, ammo, DLC starting weapon, Auto-9 chips, upgrade boards, skill points");
        ModAuthors = STR("Evasion3356");

        register_tab(STR("RoboCop Cheats"), [](CppUserModBase*) { draw_cheats_tab(); });
    }

    ~RoboCopCheatsMod() override = default;

    auto on_ui_init() -> void override
    {
        UE4SS_ENABLE_IMGUI()
    }

    // Fires for the Lua mod with the same name (Mods/RoboCopCheats/Scripts/main.lua).
    // All of a mod's Lua threads share one global table, so registering on 'lua' is enough.
    auto on_lua_start(LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua&, LuaMadeSimple::Lua&, LuaMadeSimple::Lua*) -> void override
    {
        lua.register_function("RC_UI_Clear", &rc_lua_clear);
        lua.register_function("RC_UI_AddWeapon", &rc_lua_add_weapon);
        lua.register_function("RC_UI_AddAmmo", &rc_lua_add_ammo);
        lua.register_function("RC_UI_AddBoard", &rc_lua_add_board);
        lua.register_function("RC_UI_Pop", &rc_lua_pop);
        lua.register_function("RC_UI_Status", &rc_lua_status);
        lua.register_function("RC_UI_SetDlcWeapon", &rc_lua_set_dlc_weapon);
        Output::send<LogLevel::Verbose>(STR("[RoboCopCheats] GUI bridge registered\n"));
    }

    auto on_lua_stop(LuaMadeSimple::Lua&, LuaMadeSimple::Lua&, LuaMadeSimple::Lua&, LuaMadeSimple::Lua*) -> void override
    {
        std::lock_guard lock{g_mutex};
        g_lua_connected = false;
        g_requests.clear();
        g_status = "RoboCopCheats Lua script stopped (reloading?).";
    }
};

#define ROBOCOP_CHEATS_API __declspec(dllexport)
extern "C"
{
    ROBOCOP_CHEATS_API CppUserModBase* start_mod()
    {
        return new RoboCopCheatsMod();
    }

    ROBOCOP_CHEATS_API void uninstall_mod(CppUserModBase* mod)
    {
        delete mod;
    }
}
