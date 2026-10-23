using System;
using System.IO;
using System.Text;
using System.Security.Cryptography;
public sealed class AriaBackupSink : IDisposable {
 private FileStream file; private Aes aes; private CryptoStream crypto; private byte[] authenticationKey; private bool complete; private Stream counter;
 public Stream Stream { get { return counter; } }
 public AriaBackupSink(string path,string password) {
  byte[] salt=AriaBackupCrypto.Random(32),iv=AriaBackupCrypto.Random(16),keys=AriaBackupCrypto.Derive(password,salt);
  file=new FileStream(path,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None);
  try {
   using(var writer=new BinaryWriter(file,Encoding.UTF8,true)){writer.Write(Encoding.ASCII.GetBytes("ARIABK01"));writer.Write(200000);writer.Write(salt);writer.Write(iv);}
   aes=Aes.Create();aes.Key=AriaBackupCrypto.Part(keys,0,32);aes.IV=iv;aes.Mode=CipherMode.CBC;aes.Padding=PaddingMode.PKCS7;
   authenticationKey=AriaBackupCrypto.Part(keys,32,32);crypto=new CryptoStream(file,aes.CreateEncryptor(),CryptoStreamMode.Write,true);counter=new Forward(crypto);
  } catch { file.Dispose();throw; } finally { Array.Clear(keys,0,keys.Length); }
 }
 public void Complete() {
  if(complete)return;crypto.FlushFinalBlock();file.Flush();long length=file.Length;
  byte[] mac=AriaBackupCrypto.Mac(file,length,authenticationKey);file.Position=length;file.Write(mac,0,mac.Length);file.Flush(true);complete=true;
 }
 public void Dispose(){try{if(crypto!=null)crypto.Dispose();}finally{if(aes!=null)aes.Dispose();if(file!=null)file.Dispose();if(authenticationKey!=null)Array.Clear(authenticationKey,0,authenticationKey.Length);}}
 private sealed class Forward:Stream {
  private Stream target;private long position;
  internal Forward(Stream target){this.target=target;}
  public override bool CanRead{get{return false;}} public override bool CanSeek{get{return false;}}public override bool CanWrite{get{return true;}}
  public override long Position{get{return position;}set{throw new NotSupportedException();}}public override long Length{get{return position;}}
  public override void Write(byte[] b,int o,int c){target.Write(b,o,c);position+=c;}
  public override void Flush(){target.Flush();}public override int Read(byte[] b,int o,int c){throw new NotSupportedException();}
  public override long Seek(long x,SeekOrigin y){throw new NotSupportedException();}public override void SetLength(long x){throw new NotSupportedException();}
 }

}
public static class AriaBackupCrypto {
 internal static byte[] Random(int count){byte[] b=new byte[count];using(var random=RandomNumberGenerator.Create())random.GetBytes(b);return b;}
 internal static byte[] Part(byte[] b,int start,int count){byte[] x=new byte[count];Buffer.BlockCopy(b,start,x,0,count);return x;}
 internal static byte[] Derive(string password,byte[] salt){using(var k=new Rfc2898DeriveBytes(password.Normalize().Trim(),salt,200000,HashAlgorithmName.SHA256))return k.GetBytes(64);}
 internal static byte[] Mac(FileStream file,long count,byte[] key){
  using(var mac=new HMACSHA256(key)){file.Position=0;byte[] b=new byte[65536];long remaining=count;while(remaining>0){int n=file.Read(b,0,(int)Math.Min(b.Length,remaining));if(n<=0)throw new EndOfStreamException();mac.TransformBlock(b,0,n,b,0);remaining-=n;}mac.TransformFinalBlock(new byte[0],0,0);return mac.Hash;}
 }
 private static bool Equal(byte[] a,byte[] b){int diff=a.Length^b.Length;for(int i=0;i<a.Length&&i<b.Length;i++)diff|=a[i]^b[i];return diff==0;}
 public static void Decrypt(string source,string destination,string password){
  byte[] keys=null;
  using(var file=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.Read)){
   if(file.Length<108||file.Length>2147483648L)throw new InvalidDataException("Invalid backup size.");
   byte[] salt,iv;using(var r=new BinaryReader(file,Encoding.UTF8,true)){if(Encoding.ASCII.GetString(r.ReadBytes(8))!="ARIABK01"||r.ReadInt32()!=200000)throw new InvalidDataException("Unsupported backup header.");salt=r.ReadBytes(32);iv=r.ReadBytes(16);}
   long cipherLength=file.Length-60-32;if(cipherLength<16||cipherLength%16!=0)throw new InvalidDataException("Invalid backup data.");
   keys=Derive(password,salt);
   try{
    byte[] actual=Mac(file,file.Length-32,Part(keys,32,32)),expected=new byte[32];file.Position=file.Length-32;if(file.Read(expected,0,32)!=32||!Equal(actual,expected))throw new CryptographicException("Incorrect password or damaged backup.");
    file.Position=60;
    using(var aes=Aes.Create()){aes.Key=Part(keys,0,32);aes.IV=iv;aes.Mode=CipherMode.CBC;aes.Padding=PaddingMode.PKCS7;
     using(var bounded=new Limited(file,cipherLength))
     using(var decrypt=new CryptoStream(bounded,aes.CreateDecryptor(),CryptoStreamMode.Read))
     using(var output=new FileStream(destination,FileMode.CreateNew,FileAccess.Write,FileShare.None)){decrypt.CopyTo(output,65536);output.Flush(true);}
    }
   }finally{Array.Clear(keys,0,keys.Length);}
  }
 }
 private sealed class Limited:Stream {
  private Stream source;private long remaining;
  internal Limited(Stream source,long count){this.source=source;remaining=count;}
  public override bool CanRead{get{return true;}} public override bool CanSeek{get{return false;}} public override bool CanWrite{get{return false;}}
  public override long Length{get{throw new NotSupportedException();}} public override long Position{get{throw new NotSupportedException();}set{throw new NotSupportedException();}}
  public override int Read(byte[] buffer,int offset,int count){if(remaining<=0)return 0;int n=source.Read(buffer,offset,(int)Math.Min(count,remaining));remaining-=n;return n;}
  public override void Flush(){} public override long Seek(long x,SeekOrigin y){throw new NotSupportedException();}public override void SetLength(long x){throw new NotSupportedException();}public override void Write(byte[] b,int o,int c){throw new NotSupportedException();}
 }
}