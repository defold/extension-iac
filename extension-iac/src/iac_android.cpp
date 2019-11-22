#if defined(DM_PLATFORM_ANDROID)

#include <jni.h>
#include <stdlib.h>

#include "iac.h"
#include "iac_private.h"


static JNIEnv* Attach()
{
    JNIEnv* env = 0;
    dmGraphics::GetNativeAndroidJavaVM()->AttachCurrentThread(&env, NULL);
    return env;
}

static void Detach()
{
    dmGraphics::GetNativeAndroidJavaVM()->DetachCurrentThread();
}


struct IAC
{
    IAC()
    {
        memset(this, 0, sizeof(*this));
    }
    dmScript::LuaCallbackInfo* m_Listener;

    jobject              m_IAC;
    jobject              m_IACJNI;
    jmethodID            m_Start;
    jmethodID            m_Stop;

    IACInvocation        m_StoredInvocation;

    IACCommandQueue      m_CmdQueue;
};

static IAC g_IAC;


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
    lua_pushstring(L, origin);
    lua_setfield(L, -2, "origin");
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
        dmLogError("No iac listener set. Invocation discarded.");
        g_IAC.m_StoredInvocation.Store((const char*)cmd->m_Payload, (const char*)cmd->m_Origin);
    }
    else
    {
        OnInvocation((const char*)cmd->m_Payload, (const char*)cmd->m_Origin);
    }
}


static const char* StrDup(JNIEnv* env, jstring s)
{
    if (s != NULL)
    {
        const char* str = env->GetStringUTFChars(s, 0);
        const char* dup = strdup(str);
        env->ReleaseStringUTFChars(s, str);
        return dup;
    }
    else
    {
        return 0x0;
    }
}


#ifdef __cplusplus
extern "C" {
#endif

JNIEXPORT void JNICALL Java_com_defold_iac_IACJNI_onInvocation(JNIEnv* env, jobject, jstring jpayload, jstring jorigin)
{
    IACCommand cmd;
    cmd.m_Command = IAC_INVOKE;
    cmd.m_Payload = (void*)StrDup(env, jpayload);
    cmd.m_Origin = (void*)StrDup(env, jorigin);
    IAC_Queue_Push(&g_IAC.m_CmdQueue, &cmd);
}

#ifdef __cplusplus
}
#endif


dmExtension::Result AppInitializeIAC(dmExtension::AppParams* params)
{
    IAC_Queue_Create(&g_IAC.m_CmdQueue);

    JNIEnv* env = Attach();

    jclass activity_class = env->FindClass("android/app/NativeActivity");
    jmethodID get_class_loader = env->GetMethodID(activity_class,"getClassLoader", "()Ljava/lang/ClassLoader;");
    jobject cls = env->CallObjectMethod(dmGraphics::GetNativeAndroidActivity(), get_class_loader);
    jclass class_loader = env->FindClass("java/lang/ClassLoader");
    jmethodID find_class = env->GetMethodID(class_loader, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");

    jstring str_class_name = env->NewStringUTF("com.defold.iac.IAC");
    jclass iac_class = (jclass)env->CallObjectMethod(cls, find_class, str_class_name);
    env->DeleteLocalRef(str_class_name);

    str_class_name = env->NewStringUTF("com.defold.iac.IACJNI");
    jclass iac_jni_class = (jclass)env->CallObjectMethod(cls, find_class, str_class_name);
    env->DeleteLocalRef(str_class_name);

    g_IAC.m_Start = env->GetMethodID(iac_class, "start", "(Landroid/app/Activity;Lcom/defold/iac/IIACListener;)V");
    g_IAC.m_Stop = env->GetMethodID(iac_class, "stop", "()V");
    jmethodID get_instance_method = env->GetStaticMethodID(iac_class, "getInstance", "()Lcom/defold/iac/IAC;");
    g_IAC.m_IAC = env->NewGlobalRef(env->CallStaticObjectMethod(iac_class, get_instance_method));

    jmethodID jni_constructor = env->GetMethodID(iac_jni_class, "<init>", "()V");
    g_IAC.m_IACJNI = env->NewGlobalRef(env->NewObject(iac_jni_class, jni_constructor));

    env->CallVoidMethod(g_IAC.m_IAC, g_IAC.m_Start, dmGraphics::GetNativeAndroidActivity(), g_IAC.m_IACJNI);

    Detach();
    return dmExtension::RESULT_OK;
}


dmExtension::Result AppFinalizeIAC(dmExtension::AppParams* params)
{
    JNIEnv* env = Attach();
    g_IAC.m_StoredInvocation.Release();
    env->CallVoidMethod(g_IAC.m_IAC, g_IAC.m_Stop);
    env->DeleteGlobalRef(g_IAC.m_IAC);
    env->DeleteGlobalRef(g_IAC.m_IACJNI);
    Detach();
    g_IAC.m_IAC = NULL;
    g_IAC.m_IACJNI = NULL;
    g_IAC.m_Listener = 0;
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

#endif // DM_PLATFORM_ANDROID
