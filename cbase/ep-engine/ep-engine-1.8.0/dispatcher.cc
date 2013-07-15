/* -*- Mode: C++; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/*
 *     Copyright 2010 NorthScale, Inc.
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */
#include "config.h"
#include "dispatcher.hh"
#include "objectregistry.hh"

extern "C" {
    static void* launch_dispatcher_thread(void* arg);
}

static void* launch_dispatcher_thread(void *arg) {
    Dispatcher *dispatcher = (Dispatcher*) arg;
    try {
        dispatcher->run();
    } catch (std::exception& e) {
        getLogger()->log(EXTENSION_LOG_WARNING, NULL,
                         "%s: Caught an exception: %s\n",
                         dispatcher->getName().c_str(), e.what());
    } catch(...) {
        getLogger()->log(EXTENSION_LOG_WARNING, NULL,
                         "%s: Caught a fatal exception\n",
                         dispatcher->getName().c_str());
    }
    return NULL;
}

void Dispatcher::start() {
    assert(state == dispatcher_running);
    if(pthread_create(&thread, NULL, launch_dispatcher_thread, this) != 0) {
        std::stringstream ss;
        ss << getName().c_str() << ": Initialization error!!!";
        throw std::runtime_error(ss.str().c_str());
    }
}

TaskId Dispatcher::nextTask() {
    assert (!empty());
    return readyQueue.empty() ? futureQueue.top() : readyQueue.top();
}

void Dispatcher::popNext() {
    assert (!empty());
    readyQueue.empty() ? futureQueue.pop() : readyQueue.pop();
}

void Dispatcher::moveReadyTasks(const struct timeval &tv) {
    while (!futureQueue.empty()) {
        TaskId tid = futureQueue.top();
        if (less_tv(tid->waketime, tv)) {
            readyQueue.push(tid);
            futureQueue.pop();
        } else {
            // We found all the ready stuff.
            return;
        }
    }
}

void Dispatcher::run() {
    ObjectRegistry::onSwitchThread(&engine);
    getLogger()->log(EXTENSION_LOG_INFO, NULL, "%s: Starting\n", getName().c_str());
    for (;;) {
        LockHolder lh(mutex);
        // Having acquired the lock, verify our state and break out if
        // it's changed.
        if (state != dispatcher_running) {
            break;
        }

        if (empty()) {
            // Wait forever as long as the state didn't change while
            // we grabbed the lock.
            if (state == dispatcher_running) {
                noTask();
                mutex.wait();
            }
        } else {
            struct timeval tv;
            gettimeofday(&tv, NULL);

            // Get any ready tasks out of the due queue.
            moveReadyTasks(tv);

            TaskId task = nextTask();
            assert(task);
            LockHolder tlh(task->mutex);
            if (task->state == task_dead) {
                popNext();
                continue;
            }

            if (less_tv(tv, task->waketime)) {
                idleTask->setWaketime(task->waketime);
                idleTask->setDispatcherNotifications(notifications.get());
                task = idleTask;
                taskDesc = task->getName();
            } else {
                // Otherwise, do the normal thing.
                popNext();
                taskDesc = task->getName();
            }
            tlh.unlock();

            taskStart = gethrtime();
            lh.unlock();
            rel_time_t startReltime = ep_current_time();
            try {
                running_task = true;
                if(task->run(*this, TaskId(task))) {
                    reschedule(task);
                }
            } catch (std::exception& e) {
                getLogger()->log(EXTENSION_LOG_WARNING, NULL,
                                 "%s: Exception caught in task \"%s\": %s\n",
                                 getName().c_str(), task->getName().c_str(), e.what());
            } catch(...) {
                getLogger()->log(EXTENSION_LOG_WARNING, NULL,
                                 "%s: Fatal exception caught in task \"%s\"\n",
                                 getName().c_str(), task->getName().c_str());
            }
            running_task = false;

            hrtime_t runtime((gethrtime() - taskStart) / 1000);
            JobLogEntry jle(taskDesc, runtime, startReltime);
            joblog.add(jle);
            if (runtime > task->maxExpectedDuration()) {
                slowjobs.add(jle);
            }
        }
    }

    completeNonDaemonTasks();
    state = dispatcher_stopped;
    notify();
    getLogger()->log(EXTENSION_LOG_INFO, NULL, "%s: Exited\n", getName().c_str());
}

void Dispatcher::stop(bool force) {
    LockHolder lh(mutex);
    if (state == dispatcher_stopped || state == dispatcher_stopping) {
        return;
    }
    forceTermination = force;
    getLogger()->log(EXTENSION_LOG_INFO, NULL, "%s: Stopping\n", getName().c_str());
    state = dispatcher_stopping;
    notify();
    lh.unlock();
    pthread_join(thread, NULL);
    getLogger()->log(EXTENSION_LOG_INFO, NULL, "%s: Stopped\n", getName().c_str());
}

void Dispatcher::schedule(shared_ptr<DispatcherCallback> callback,
                          TaskId *outtid,
                          const Priority &priority,
                          double sleeptime,
                          bool isDaemon,
                          bool mustComplete) {
    LockHolder lh(mutex);
    TaskId task(new Task(callback, priority.getPriorityValue(), sleeptime,
                         isDaemon, mustComplete));
    if (outtid) {
        *outtid = TaskId(task);
    }

    getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                     "%s: Schedule a task \"%s\"",
                     getName().c_str(), task->getName().c_str());

    futureQueue.push(task);
    notify();
}

void Dispatcher::wake(TaskId task, TaskId *outtid) {
    cancel(task);
    LockHolder lh(mutex);
    TaskId oldTask(task);
    TaskId newTask(new Task(*oldTask));
    if (outtid) {
        *outtid = TaskId(task);
    }

    getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                     "%s: Wake a task \"%s\"",
                     getName().c_str(), task->getName().c_str());

    futureQueue.push(newTask);
    notify();
}

void Dispatcher::snooze(TaskId t, double sleeptime) {
    getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                     "%s: Snooze a task \"%s\"",
                     getName().c_str(), t->getName().c_str());
    t->snooze(sleeptime);
}

void Dispatcher::cancel(TaskId t) {
    getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                     "%s: Cancel a task \"%s\"",
                     getName().c_str(), t->getName().c_str());
    t->cancel();
}

void Dispatcher::reschedule(TaskId task) {
    // If the task is already in the queue it'll get run twice
    LockHolder lh(mutex);
    getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                     "%s: Reschedule a task \"%s\"",
                     getName().c_str(), task->getName().c_str());
    futureQueue.push(task);
    notify();
}

void Dispatcher::completeNonDaemonTasks() {
    LockHolder lh(mutex);
    while (!empty()) {
        TaskId task = nextTask();
        popNext();
        assert(task);
        // Skip a daemon task
        if (task->isDaemonTask) {
            getLogger()->log(EXTENSION_LOG_INFO, NULL,
                             "%s: Skipping daemon task \"%s\" during shutdown\n",
                             getName().c_str(), task->getName().c_str());

            continue;
        }

        if (task->blockShutdown || !forceTermination) {
            LockHolder tlh(task->mutex);
            if (task->state == task_running) {
                tlh.unlock();
                getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                                 "%s: Running task \"%s\" during shutdown",
                                 getName().c_str(), task->getName().c_str());
                try {
                    while (task->run(*this, TaskId(task))) {
                        getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                                         "%s: Keep on running task \"%s\" during shutdown",
                                         getName().c_str(), task->getName().c_str());
                    }
                } catch (std::exception& e) {
                    getLogger()->log(EXTENSION_LOG_WARNING, NULL,
                                     "%s: Exception caught in task \"%s\" "
                                     "during shutdown: \"%s\"",
                                     getName().c_str(), task->getName().c_str(), e.what());
                } catch (...) {
                    getLogger()->log(EXTENSION_LOG_WARNING, NULL,
                                     "%s: Fatal exception caught in task \"%s\" "
                                     "during shutdown",
                                     getName().c_str(), task->getName().c_str());
                }
                getLogger()->log(EXTENSION_LOG_DEBUG, NULL,
                                 "%s: Task \"%s\" completed during shutdown",
                                 getName().c_str(), task->getName().c_str());
            }
        } else {
            getLogger()->log(EXTENSION_LOG_INFO, NULL,
                             "%s: Skipping task \"%s\" during shutdown",
                             getName().c_str(), task->getName().c_str());
        }
    }

    getLogger()->log(EXTENSION_LOG_INFO, NULL,
                     "%s: Completed all the non-daemon tasks as part of shutdown\n",
                     getName().c_str());
}

bool IdleTask::run(Dispatcher &d, TaskId) {
    LockHolder lh(d.mutex);
    if (d.notifications.get() == dnotifications) {
        d.mutex.wait(waketime);
    }
    return false;
}
