#if defined(DM_PLATFORM_ANDROID) || defined(DM_PLATFORM_IOS)

#include <dmsdk/sdk.h>

#include "iac.h"
#include "iac_private.h"
#include <string.h>
#include <stdlib.h>

void IAC_Queue_Create(IACCommandQueue* queue)
{
    queue->m_Mutex = dmMutex::New();
}

void IAC_Queue_Destroy(IACCommandQueue* queue)
{
    dmMutex::Delete(queue->m_Mutex);
}

void IAC_Queue_Push(IACCommandQueue* queue, IACCommand* cmd)
{
    DM_MUTEX_SCOPED_LOCK(queue->m_Mutex);

    if(queue->m_Commands.Full())
    {
        queue->m_Commands.OffsetCapacity(2);
    }
    queue->m_Commands.Push(*cmd);
}

void IAC_Queue_Flush(IACCommandQueue* queue, IACCommandFn fn, void* ctx)
{
    assert(fn != 0);
    if (queue->m_Commands.Empty())
    {
        return;
    }

    DM_MUTEX_SCOPED_LOCK(queue->m_Mutex);

    for(uint32_t i = 0; i != queue->m_Commands.Size(); ++i)
    {
        fn(&queue->m_Commands[i], ctx);
    }
    queue->m_Commands.SetSize(0);
}

#endif // DM_PLATFORM_ANDROID || DM_PLATFORM_IOS
