#if defined(DM_PLATFORM_IOS)

#include "iac.h"
#include "iac_private.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdlib.h>


struct IAC
{
    IAC()
    {
        Clear();
    }

    void Clear() {
        m_SceneDelegate = 0;
        m_Listener = 0;
    }
    dmScript::LuaCallbackInfo*  m_Listener;

    id<UISceneDelegate>   m_SceneDelegate;

    IACInvocation               m_StoredInvocation;

    IACCommandQueue             m_CmdQueue;
} g_IAC;


static void QueueURL(NSURL* url, NSString* sourceApplication)
{
    const char* payload = [[url absoluteString] UTF8String];
    if (!payload)
        return;

    const char* origin = sourceApplication ? [sourceApplication UTF8String] : 0;
    IACCommand cmd;
    cmd.m_Command = IAC_INVOKE;
    cmd.m_Payload = strdup(payload);
    cmd.m_Origin = origin ? strdup(origin) : 0;
    IAC_Queue_Push(&g_IAC.m_CmdQueue, &cmd);
}


@interface IACSceneDelegate : NSObject <UISceneDelegate>

@end


@implementation IACSceneDelegate

- (void)scene:(UIScene*)scene openURLContexts:(NSSet<UIOpenURLContext*>*)contexts
{
    for (UIOpenURLContext* context in contexts)
        QueueURL(context.URL, context.options.sourceApplication);
}

- (void)scene:(UIScene*)scene continueUserActivity:(NSUserActivity*)userActivity
{
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb])
        QueueURL(userActivity.webpageURL, nil);
}

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options
{
    [self scene:scene openURLContexts:options.URLContexts];
    for (NSUserActivity* userActivity in options.userActivities)
        [self scene:scene continueUserActivity:userActivity];
}

@end


struct IACSceneDelegateRegister
{
    IACSceneDelegateRegister() {
        g_IAC.Clear();
        // Scene connection can deliver links before Lua initialization. Keep the
        // queue alive for as long as the registered observer can receive events.
        IAC_Queue_Create(&g_IAC.m_CmdQueue);
        g_IAC.m_SceneDelegate = [[IACSceneDelegate alloc] init];
        dmExtension::RegisteriOSUISceneDelegate(g_IAC.m_SceneDelegate);
    }
    ~IACSceneDelegateRegister() {
        dmExtension::UnregisteriOSUISceneDelegate(g_IAC.m_SceneDelegate);
        [g_IAC.m_SceneDelegate release];
        IAC_Queue_Destroy(&g_IAC.m_CmdQueue);
        g_IAC.Clear();
    }
};
IACSceneDelegateRegister g_IACSceneDelegateRegister;


static void OnInvocation(const char* payload, const char *origin)
{
    IAC* iac = &g_IAC;

    lua_State* L = dmScript::GetCallbackLuaContext(iac->m_Listener);
    int top = lua_gettop(L);

    if (!dmScript::SetupCallback(iac->m_Listener))
    {
        assert(top == lua_gettop(L));
        return;
    }

    lua_createtable(L, 0, 2);
    lua_pushstring(L, payload);
    lua_setfield(L, -2, "url");
    if (origin) {
        lua_pushstring(L, origin);
        lua_setfield(L, -2, "origin");
    }
    lua_pushnumber(L, DM_IAC_EXTENSION_TYPE_INVOCATION);

    int ret = lua_pcall(L, 3, 0, 0);
    if (ret != 0) {
        dmLogError("Error running iac callback: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }

    dmScript::TeardownCallback(iac->m_Listener);
    assert(top == lua_gettop(L));
}


int IAC_PlatformSetListener(lua_State* L)
{
    IAC* iac = &g_IAC;

    if (iac->m_Listener)
        dmScript::DestroyCallback(iac->m_Listener);

    iac->m_Listener = dmScript::CreateCallback(L, 1);

    // handle stored invocation
    const char* payload, *origin;
    if(iac->m_StoredInvocation.Get(&payload, &origin))
        OnInvocation(payload, origin);

    return 0;
}


static void HandleInvocation(const IACCommand* cmd)
{
    if (!g_IAC.m_Listener)
    {
        g_IAC.m_StoredInvocation.Store((const char*)cmd->m_Payload, (const char*)cmd->m_Origin);
    }
    else
    {
        OnInvocation((const char*)cmd->m_Payload, (const char*)cmd->m_Origin);
    }
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

    free((void*)cmd->m_Payload);
    free((void*)cmd->m_Origin);
}

dmExtension::Result UpdateIAC(dmExtension::Params* params)
{
    IAC_Queue_Flush(&g_IAC.m_CmdQueue, IAC_OnCommand, 0);
    return dmExtension::RESULT_OK;
}


DM_DECLARE_EXTENSION(IACExt, "IAC", 0, 0, InitializeIAC, UpdateIAC, 0, FinalizeIAC)

#endif // DM_PLATFORM_IOS