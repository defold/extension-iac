#if defined(DM_PLATFORM_ANDROID) || defined(DM_PLATFORM_IOS)

#ifndef IAC_PRIVATE_H
#define IAC_PRIVATE_H

#include <stdlib.h>
#include <dmsdk/sdk.h>

struct IACInvocation
{
    IACInvocation()
    {
        memset(this, 0x0, sizeof(IACInvocation));
    }

    bool Get(const char** payload, const char** origin)
    {
        if(!m_Pending)
            return false;
        m_Pending = false;
        *payload = m_Payload;
        *origin = m_Origin;
        return true;
    }

    void Store(const char* payload, const char* origin)
    {
        Release();
        if(payload)
        {
            m_Payload = strdup(payload);
            m_Pending = true;
        }
        if(origin)
        {
            m_Origin = strdup(origin);
            m_Pending = true;
        }
    }

    void Release()
    {
        free((void*)m_Payload);
        free((void*)m_Origin);
        memset(this, 0x0, sizeof(IACInvocation));
    }

    const char* m_Payload;
    const char* m_Origin;
    bool        m_Pending;
};

enum EIACCommand
{
	IAC_INVOKE,
};

struct DM_ALIGNED(16) IACCommand
{
    IACCommand()
    {
        memset(this, 0, sizeof(IACCommand));
    }

    // Used for storing eventual callback info (if needed)
    dmScript::LuaCallbackInfo* m_Callback;

    // The actual command payload
    int32_t  	m_Command;
    const char* m_Payload;
    const char* m_Origin;
};

struct IACCommandQueue
{
    dmArray<IACCommand>  m_Commands;
    dmMutex::HMutex      m_Mutex;
};

typedef void (*IACCommandFn)(IACCommand* cmd, void* ctx);

void IAC_Queue_Create(IACCommandQueue* queue);
void IAC_Queue_Destroy(IACCommandQueue* queue);
// The command is copied by value into the queue
void IAC_Queue_Push(IACCommandQueue* queue, IACCommand* cmd);
void IAC_Queue_Flush(IACCommandQueue* queue, IACCommandFn fn, void* ctx);

#endif

#endif // DM_PLATFORM_ANDROID || DM_PLATFORM_IOS
