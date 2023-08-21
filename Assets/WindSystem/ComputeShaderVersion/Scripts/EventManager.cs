using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class EventManager
{
    public static void AddEvent(string eventName, Action callback)
    {
        CommonAddEvent(eventName, callback);
    }

    public static void AddEvent<T>(string eventName, Action<T> callback)
    {
        CommonAddEvent(eventName, callback);
    }

    public static void AddEvent<T, T1>(string eventName, Action<T, T1> callback)
    {
        CommonAddEvent(eventName, callback);
    }

    public static void AddEvent<T, T1, T2>(string eventName, Action<T, T1, T2> callback)
    {
        CommonAddEvent(eventName, callback);
    }
    
    private static void CommonAddEvent(string eventName, Delegate callback)
    {
        List<Delegate> actions = null;

        if (_events.TryGetValue(eventName, out actions))
        {
            actions.Add(callback);
        }
        else
        {
            actions = new List<Delegate>();
            actions.Add(callback);
            _events.Add(eventName, actions);
        }
    }

    private static void CommonRemoveEvent(string eventName, Delegate callback)
    {
        List<Delegate> actions = null;

        if (_events.TryGetValue(eventName, out actions))
        {
            actions.Remove(callback);
            if (actions.Count == 0)
            {
                _events.Remove(eventName);
            }
        }
    }

    public static void RemoveEvent(string eventName, Action callback)
    {
        CommonRemoveEvent(eventName, callback);
    }
    
    public static void RemoveEvent<T>(string eventName, Action<T> callback)
    {
        CommonRemoveEvent(eventName, callback);
    }

    public static void RemoveEvent<T, T1>(string eventName, Action<T, T1> callback)
    {
        CommonRemoveEvent(eventName, callback);
    }

    public static void RemoveEvent<T, T1, T2>(string eventName, Action<T, T1, T2> callback)
    {
        CommonRemoveEvent(eventName, callback);
    }

    public static void RemoveAllEvents()
    {
        _events.Clear();
    }
    
    public static void DispatchEvent(string eventName)
    {
        List<Delegate> actions = null;

        if (_events.ContainsKey(eventName))
        {
            _events.TryGetValue(eventName, out actions);
            foreach (var a in actions)
            {
                a.DynamicInvoke();
            }
        }
    }
    
    public static void DispatchEvent<T>(string eventName, T arg)
    {
        List<Delegate> actions = null;

        if (_events.ContainsKey(eventName))
        {
            _events.TryGetValue(eventName, out actions);
            foreach (var a in actions)
            {
                a.DynamicInvoke(arg);
            }
        }
    }

    public static void DispatchEvent<T, T1>(string eventName, T arg, T1 arg1)
    {
        List<Delegate> actions = null;

        if (_events.ContainsKey(eventName))
        {
            _events.TryGetValue(eventName, out actions);
            foreach (var act in actions)
            {
                act.DynamicInvoke(arg, arg1);
            }
        }
    }

    public static void DispatchEvent<T, T1, T2>(string eventName, T arg, T1 arg1, T2 arg2)
    {
        List<Delegate> actions = null;

        if (_events.ContainsKey(eventName))
        {
            _events.TryGetValue(eventName, out actions);
            foreach (var act in actions)
            {
                act.DynamicInvoke(arg, arg1, arg2);
            }
        }
    }

    public static Dictionary<string, List<Delegate>> _events = new Dictionary<string, List<Delegate>>();
}