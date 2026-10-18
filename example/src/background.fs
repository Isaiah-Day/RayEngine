 in vec2 fragTexCoord;                                                                                                                                                                       
out vec4 finalColor;                                                                                                                                                                        
uniform float u_time;                                                                                                                                                                       
uniform vec2 u_size;                                                                                                                                                                        
                                                                                                                                                                                          
float cosRange(float amt, float range, float minimum) {                                                                                                                                     
   return (((1.0 + cos(radians(amt))) * 0.5) * range) + minimum;                                                                                                                            
}                                                                                                                                                                                           
                                                                                                                                                                                             
void main()                                                                                                                                                                                 
{                                                                                                                                                                                           
      const int zoom = 40;                                                                                                                                                                    
      const float brightness = 0.975;                                                                                                                                                         
   float time = 5;                                    // use the live uniform                                                                                                          
   vec2 uv = fragTexCoord;                                 // already 0..1                                                                                                                  
   vec2 p  = 2.0*fragTexCoord - 1.0;                       // center to -1..1                                                                                                               
   // optionally preserve aspect ratio:                                                                                                                                                     
   // p.x *= u_size.x / u_size.y;                                                                                                                                                           
                                                                                                                                                                                             
   float ct = cosRange(time*5.0, 3.0, 1.1);                                                                                                                                                 
   float xBoost = cosRange(time*0.2, 5.0, 5.0);                                                                                                                                             
   float yBoost = cosRange(time*0.1, 10.0, 5.0);                                                                                                                                            
   float fScale = cosRange(time * 15.5, 1.25, 0.5);                                                                                                                                         
                                                                                                                                                                                             
   for(int i=1;i<zoom;i++) {                                                                                                                                                                
      float _i = float(i);                                                                                                                                                                  
      vec2 newp=p;                                                                                                                                                                          
      newp.x+=0.25/_i*sin(_i*p.y+time*cos(ct)*0.5/20.0+0.005*_i)*fScale+xBoost;                                                                                                             
      newp.y+=0.25/_i*sin(_i*p.x+time*ct*0.3/40.0+0.03*float(i+15))*fScale+yBoost;                                                                                                          
      p=newp;                                                                                                                                                                               
   }                                                                                                                                                                                        
                                                                                                                                                                                             
   vec3 col=vec3(0.5*sin(3.0*p.x)+0.5,0.5*sin(3.0*p.y)+0.5,sin(p.x+p.y));                                                                                                                   
   col *= brightness;                                                                                                                                                                       
                                                                                                                                                                                             
      // Vignette as a color multiplier, not alpha                                                                                                                                            
   float vigAmt = 5.0;                                                                                                                                                                      
   float vignette = (1.-vigAmt*(uv.y-.5)*(uv.y-.5))*(1.-vigAmt*(uv.x-.5)*(uv.x-.5));                                                                                                        
   col *= 1.5 * vignette;                                                                                                                                                                   
                                                                                                                                                       
   finalColor = vec4(vec3(min(col[0], 255), min(255,col[1]), min(255,col[2])), 1.0);                            // opaque; col can go slightly negative -> dark                                                                                  
}  