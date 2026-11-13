// WeaponSpawner GUI tab (UE4SS C++ mod).
//
// This DLL only draws the "Weapon Spawner" tab in the UE4SS GUI window and queues clicks.
// All game interaction stays in Scripts/main.lua (the code path verified in game).
//
// Bridge: when the Lua mod of the same name starts, we register these globals in its state:
//   WS_UI_Clear()                       Lua is (re)starting; forget the lists
//   WS_UI_AddWeapon(display, asset)     add a weapon button
//   WS_UI_AddAmmo(display, asset)       add an ammo button
//   WS_UI_Pop() -> string|nil           next queued request: "give <asset>" / "ammo <asset> <amount>"
//   WS_UI_Status(msg)                   status line shown at the top of the tab
// The GUI runs on UE4SS's render thread and Lua polls on the game thread, so all shared
// state is behind one mutex.

#include <Mod/CppUserModBase.hpp>
#include <UE4SSProgram.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <imgui.h>

#include <algorithm>
#include <cctype>
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
    std::vector<WeaponEntry> g_ammo; // same shape: display label + asset name
    std::deque<std::string> g_requests;
    std::string g_status = "Waiting for the WeaponSpawner Lua script to start...";
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

    int ws_lua_clear(const LuaMadeSimple::Lua&)
    {
        std::lock_guard lock{g_mutex};
        g_weapons.clear();
        g_ammo.clear();
        g_requests.clear();
        g_lua_connected = true;
        g_status = "Ready. Load into a level, then click a weapon.";
        return 0;
    }

    int ws_lua_add_weapon(const LuaMadeSimple::Lua& lua)
    {
        if (!lua.is_string()) return 0;
        std::string display{lua.get_string()};
        if (!lua.is_string()) return 0;
        std::string asset{lua.get_string()};
        std::lock_guard lock{g_mutex};
        g_weapons.push_back({std::move(display), std::move(asset)});
        return 0;
    }

    int ws_lua_add_ammo(const LuaMadeSimple::Lua& lua)
    {
        if (!lua.is_string()) return 0;
        std::string display{lua.get_string()};
        if (!lua.is_string()) return 0;
        std::string asset{lua.get_string()};
        std::lock_guard lock{g_mutex};
        g_ammo.push_back({std::move(display), std::move(asset)});
        return 0;
    }

    int ws_lua_pop(const LuaMadeSimple::Lua& lua)
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

    int ws_lua_status(const LuaMadeSimple::Lua& lua)
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

    void draw_spawner_tab()
    {
        if (!bind_ue4ss_imgui()) return;

        static char filter[64]{};
        static int ammo_amount = 200;

        std::vector<WeaponEntry> weapons;
        std::vector<WeaponEntry> ammo;
        std::string status;
        bool connected;
        {
            std::lock_guard lock{g_mutex};
            weapons = g_weapons;
            ammo = g_ammo;
            status = g_status;
            connected = g_lua_connected;
        }

        ImGui::TextWrapped("%s", status.c_str());
        if (!connected)
        {
            ImGui::TextWrapped("Make sure Mods/WeaponSpawner/Scripts/main.lua exists and WeaponSpawner is enabled in mods.txt.");
            return;
        }
        ImGui::Separator();

        ImGui::SetNextItemWidth(220.0f);
        ImGui::InputTextWithHint("##filter", "Filter weapons / ammo...", filter, sizeof(filter));
        ImGui::SameLine();
        if (ImGui::Button("Clear")) filter[0] = '\0';

        if (!ImGui::BeginTable("ws_table", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_BordersInnerV)) return;
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
} // namespace

class WeaponSpawnerMod : public CppUserModBase
{
  public:
    WeaponSpawnerMod() : CppUserModBase()
    {
        ModName = STR("WeaponSpawner");
        ModVersion = STR("1.0");
        ModDescription = STR("Clickable weapon/ammo spawner tab for RoboCop: Rogue City");
        ModAuthors = STR("Evasion3356");

        register_tab(STR("Weapon Spawner"), [](CppUserModBase*) { draw_spawner_tab(); });
    }

    ~WeaponSpawnerMod() override = default;

    auto on_ui_init() -> void override
    {
        UE4SS_ENABLE_IMGUI()
    }

    // Fires for the Lua mod with the same name (Mods/WeaponSpawner/Scripts/main.lua).
    // All of a mod's Lua threads share one global table, so registering on 'lua' is enough.
    auto on_lua_start(LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua&, LuaMadeSimple::Lua&, LuaMadeSimple::Lua*) -> void override
    {
        lua.register_function("WS_UI_Clear", &ws_lua_clear);
        lua.register_function("WS_UI_AddWeapon", &ws_lua_add_weapon);
        lua.register_function("WS_UI_AddAmmo", &ws_lua_add_ammo);
        lua.register_function("WS_UI_Pop", &ws_lua_pop);
        lua.register_function("WS_UI_Status", &ws_lua_status);
        Output::send<LogLevel::Verbose>(STR("[WeaponSpawner] GUI bridge registered\n"));
    }

    auto on_lua_stop(LuaMadeSimple::Lua&, LuaMadeSimple::Lua&, LuaMadeSimple::Lua&, LuaMadeSimple::Lua*) -> void override
    {
        std::lock_guard lock{g_mutex};
        g_lua_connected = false;
        g_requests.clear();
        g_status = "WeaponSpawner Lua script stopped (reloading?).";
    }
};

#define WEAPON_SPAWNER_API __declspec(dllexport)
extern "C"
{
    WEAPON_SPAWNER_API CppUserModBase* start_mod()
    {
        return new WeaponSpawnerMod();
    }

    WEAPON_SPAWNER_API void uninstall_mod(CppUserModBase* mod)
    {
        delete mod;
    }
}
