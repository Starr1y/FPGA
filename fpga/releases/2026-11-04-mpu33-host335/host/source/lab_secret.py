"""Windows current-user DPAPI storage; never serializes plaintext secrets."""
import ctypes,os
from ctypes import wintypes as T
from pathlib import Path

class Blob(ctypes.Structure):
    _fields_=[('size',T.DWORD),('data',ctypes.POINTER(ctypes.c_ubyte))]

def protect(data,decrypt=False):
    if os.name!='nt':raise ValueError('本机记住密钥需要Windows加密服务')
    crypt=ctypes.WinDLL('crypt32',use_last_error=True);kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    buffer=ctypes.create_string_buffer(data);src=Blob(len(data),ctypes.cast(buffer,ctypes.POINTER(ctypes.c_ubyte)));out=Blob()
    entropy=ctypes.create_string_buffer(b'TangLab-score-key-v1');ent=Blob(len(entropy.raw),ctypes.cast(entropy,ctypes.POINTER(ctypes.c_ubyte)))
    kernel.LocalFree.argtypes=[ctypes.c_void_p];kernel.LocalFree.restype=ctypes.c_void_p
    if decrypt:
        fn=crypt.CryptUnprotectData;fn.argtypes=[ctypes.POINTER(Blob),ctypes.c_void_p,ctypes.POINTER(Blob),ctypes.c_void_p,ctypes.c_void_p,T.DWORD,ctypes.POINTER(Blob)]
        ok=fn(ctypes.byref(src),None,ctypes.byref(ent),None,None,1,ctypes.byref(out))
    else:
        fn=crypt.CryptProtectData;fn.argtypes=[ctypes.POINTER(Blob),T.LPCWSTR,ctypes.POINTER(Blob),ctypes.c_void_p,ctypes.c_void_p,T.DWORD,ctypes.POINTER(Blob)]
        ok=fn(ctypes.byref(src),'TangLab AI',ctypes.byref(ent),None,None,1,ctypes.byref(out))
    if not ok:raise ValueError('无法读取本机保存的密钥，请重新填写并保存' if decrypt else 'Windows密钥加密失败，未保存密钥')
    try:return ctypes.string_at(out.data,out.size)
    finally:kernel.LocalFree(ctypes.cast(out.data,ctypes.c_void_p))

def save_key(folder,key):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    path=folder/'ai-key.dpapi'
    if not key:path.unlink(missing_ok=True);return
    encrypted=protect(key.encode('utf-8'));tmp=folder/'ai-key.dpapi.tmp';tmp.write_bytes(encrypted);os.replace(tmp,path)

def load_key(folder):
    path=Path(folder)/'ai-key.dpapi'
    return protect(path.read_bytes(),True).decode('utf-8') if path.exists() else ''
