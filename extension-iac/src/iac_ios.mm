#if defined(DM_PLATFORM_IOS)

#include "iac.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


struct IAC
{
    IAC()
    {
        Clear();
    }

    void Clear() {
        m_AppDelegate = 0;
        m_Listener = 0;

        if (m_StoredInvocation) {
             m_StoredInvocation.Release()
        }
    }
    dmScript::LuaCallbackInfo*  m_Listener;

    id<UIApplicationDelegate>   m_AppDelegate;
    NSMutableDictionary*        m_SavedInvocation;
    bool                        m_LaunchInvocation;

    IACInvocation               m_StoredInvocation;

    IACCommandQueue             m_CmdQueue;
} g_IAC;


static void ObjCToLua(lua_State*L, id obj)
{
    if ([obj isKindOfClass:[NSString class]]) {
        const char* str = [((NSString*) obj) UTF8String];
        lua_pushstring(L, str);
    } else if ([obj isKindOfClass:[NSNumber class]]) {
        lua_pushnumber(L, [((NSNumber*) obj) doubleValue]);
    } else if ([obj isKindOfClass:[NSNull class]]) {
        lua_pushnil(L);
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary* dict = (NSDictionary*) obj;
        lua_createtable(L, 0, [dict count]);
        for (NSString* key in dict) {
            lua_pushstring(L, [key UTF8String]);
            id value = [dict objectForKey:key];
            ObjCToLua(L, (NSDictionary*) value);
            lua_rawset(L, -3);
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        NSArray* a = (NSArray*) obj;
        lua_createtable(L, [a count], 0);
        for (int i = 0; i < [a count]; ++i) {
            ObjCToLua(L, [a objectAtIndex: i]);
            lua_rawseti(L, -2, i+1);
        }
    } else {
        dmLogWarning("Unsupported iac payload value '%s' (%s)", [[obj description] UTF8String], [[[obj class] description] UTF8String]);
        lua_pushnil(L);
    }
}


static void RunIACListener(NSDictionary *userdata, uint32_t type)
{
    if (g_IAC.m_Listener)
    {
        lua_State* L = dmScript::GetCallbackLuaContext(g_IAC.m_Listener);
        int top = lua_gettop(L);

        if (!dmScript::SetupCallback(g_IAC.m_Listener))
        {
            assert(top == lua_gettop(L));
            return;
        }

        ObjCToLua(L, userdata);
        lua_pushnumber(L, type);

        int ret = lua_pcall(L, 3, 0, 0);
        if (ret != 0) {
            dmLogError("Error running iac callback: %s", lua_tostring(L, -1));
            lua_pop(L, 1);
        }

        dmScript::TeardownCallback(g_IAC.m_Listener);
        assert(top == lua_gettop(L));
    }
}


@interface IACAppDelegate : NSObject <UIApplicationDelegate>

@end


@implementation IACAppDelegate

-(BOOL) application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation{
    dmLogError("openURL");

    // Handle invocations
    if(g_IAC.m_LaunchInvocation)
    {
        // If this is the launch invocation saved, skip this first call to openURL as it is the same invocation and we want to store it!
        g_IAC.m_LaunchInvocation = false;
        return YES;
    }
    if (g_IAC.m_SavedInvocation)
    {
        [g_IAC.m_SavedInvocation release];
        g_IAC.m_SavedInvocation = 0;
        if (!g_IAC.m_Listener)
        {
            dmLogWarning("No iac listener set. Invocation discarded.");
        }
    }
    NSMutableDictionary* userdata = [[NSMutableDictionary alloc]initWithCapacity:2];
    [userdata setObject:[url absoluteString] forKey:@"url"];
    if( sourceApplication )
    {
        [userdata setObject:sourceApplication forKey:@"origin"];
    }
    if (!g_IAC.m_Listener)
    {
        g_IAC.m_SavedInvocation = userdata;
    }
    else
    {
        RunIACListener(userdata, DM_IAC_EXTENSION_TYPE_INVOCATION);
        [userdata release];
    }
    return YES;
}


- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    dmLogError("willFinishLaunchingWithOptions");

    // Handle invocations launching the app.
    // willFinishLaunchingWithOptions is called prior to any scripts so we are garuanteed to have this information at any time set_listener is called!
    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
        g_IAC.m_SavedInvocation = [[NSMutableDictionary alloc]initWithCapacity:2];
        if (launchOptions[UIApplicationLaunchOptionsSourceApplicationKey]) {
            [g_IAC.m_SavedInvocation setObject:[launchOptions valueForKey:UIApplicationLaunchOptionsSourceApplicationKey] forKey:@"origin"];
        }
        if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
            [g_IAC.m_SavedInvocation setObject:[[launchOptions valueForKey:UIApplicationLaunchOptionsURLKey] absoluteString] forKey:@"url"];
        }
        g_IAC.m_LaunchInvocation = true;
    }
    // Return YES prevents OpenURL from being called, we need to do this as other extensions might and therefore internally handle OpenURL also being called.
    return YES;
}

@end



struct IACAppDelegateRegister
{
    IACAppDelegateRegister() {
        dmLogError("IACAppDelegateRegister");
        g_IAC.Clear();
        g_IAC.m_AppDelegate = [[IACAppDelegate alloc] init];
        dmExtension::RegisteriOSUIApplicationDelegate(g_IAC.m_AppDelegate);
    }
    ~IACAppDelegateRegister() {
        dmExtension::UnregisteriOSUIApplicationDelegate(g_IAC.m_AppDelegate);
        [g_IAC.m_AppDelegate release];
        g_IAC.Clear();
    }
};
IACAppDelegateRegister g_IACAppDelegateRegister;



int IAC_PlatformSetListener(lua_State* L)
{
    IAC* iac = &g_IAC;

    if (iac->m_Listener)
        dmScript::DestroyCallback(iac->m_Listener);

    iac->m_Listener = dmScript::CreateCallback(L, 1);

    if (g_IAC.m_SavedInvocation)
    {
        RunIACListener(g_IAC.m_SavedInvocation, DM_IAC_EXTENSION_TYPE_INVOCATION);
        [g_IAC.m_SavedInvocation release];
        g_IAC.m_SavedInvocation = 0;
    }
    return 0;
}


dmExtension::Result AppInitializeIAC(dmExtension::AppParams* params)
{
    return dmExtension::RESULT_OK;
}


dmExtension::Result AppFinalizeIAC(dmExtension::AppParams* params)
{
    IAC_Queue_Destroy(&g_IAC.m_CmdQueue);
    return dmExtension::RESULT_OK;
}


dmExtension::Result InitializeIAC(dmExtension::Params* params)
{
    return dmIAC::Initialize(params);
}


dmExtension::Result FinalizeIAC(dmExtension::Params* params)
{
    if (params->m_L == dmScript::GetCallbackLuaContext(g_IAC.m_Listener)) {
        dmScript::DestroyCallback(g_IAC.m_Listener);
        g_IAC.m_Listener = 0;
    }
    return dmIAC::Finalize(params);
}

static void IAC_OnCommand(IACCommand* cmd, void*)
{
    switch (cmd->m_Command)
    {
    case IAC_INVOKE:
        HandleInvocation(cmd);
        break;

    default:
        assert(false);
    }

    if (cmd->m_Payload) {
        free(cmd->m_Payload);
    }
    if (cmd->m_Origin) {
        free(cmd->m_Origin);
    }
}

dmExtension::Result UpdateIAC(dmExtension::Params* params)
{
    IAC_Queue_Flush(&g_IAC.m_CmdQueue, IAC_OnCommand, 0);
    return dmExtension::RESULT_OK;
}


DM_DECLARE_EXTENSION(IACExt, "IAC", AppInitializeIAC, AppFinalizeIAC, InitializeIAC, UpdateIAC, 0, FinalizeIAC)

#endif // DM_PLATFORM_IOS
