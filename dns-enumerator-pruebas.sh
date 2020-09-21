#!/bin/bash
#Es un script que combina una serie de herramientas
#para enumerar los subdominios de un dominio asi como extraer ips, rangos ip, etc
#para usar este script primero vamos a https://bgp.he.net/ y buscamos el dominio objetivo
#como por ejemplo paypal y copiamos los resultados los pegamos en un txt que pasaremos
#como argumento a este script

#esto solo se pide para ponerle ese nombre  a los resultados de la enumeracion y sen identificables
echo "ingresa un dominio objetivo"
read -p 'objetivo: ' objetivo
#es la ruta donde se guardaran todos los .txt con toda la info-resultante
echo "ejemplo: /home/user , tenga cuidado de no poner la ultima diagonal de la ruta"
read -p 'ruta enumeracion: ' ruta
#Toma  lo copiado de https://bgp.he.net/  pegado en un txt que pasamos como argumento y extrae los rangos de ip
cat $1 | grep -E -o "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(0\/[0-9][0-9])?" | tee -a $ruta/$objetivo-rangosip.txt

#la linea de abajo funciona pero pues basicamente tambien convierte los rangos  en ips pero se ve mas mamon desplegado como en la siguiente fase
#for rip in $(cat $ruta/$objetivo-rangosip.txt); do prips $rip; done >> $ruta/$objetivo-ips.txt

#convierte los rangos de ip en  ips:(esta es la chida que se ve mamona)
for rip in $(cat $ruta/$objetivo-rangosip.txt);
do
prips $rip | tee -a $ruta/$objetivo-ips.txt | hakrevdns -d | tee -a $ruta/$objetivo-esubdomains.txt ;
done

#toma el archivo objetivo-esubdomains.txt y busca mas subdominios con assetfinder
for subs in $(cat $ruta/$objetivo-esubdomains.txt);
do
#assetfinder --subs-only $subs | tee -a $ruta/$objetivo-esubdomains.txt;
assetfinder --subs-only $subs | uniq | tee -a $ruta/$objetivo-esubdomains.txt;
done
# la siguiente linea es bastante compleja , se encarga de limpiar el archivo para evitar repeticiones , el comando uniq requiere de que el txt este acomodado alfabeticamente para ser
#preciso , es decir requiere de sort , sort -u ordena alfabeticamente y despues elimina las lineas repetidas , ahora piensalo en esta enumeracion podemos estar en la lista buscando
#subdominios para  un subdomunio que empieza con la letra d y que nos de un subdominio que empieze con a como resultado , a la hora de hacer sort -u en el intento de evitar duplicados
# y evitar buscar en subdominios que ya buscamos previamente y caer en un bucle infinito de busqueda , sort -u ordenara alfabeticamente y este nuevo subdominio que encontramos
#que empieza con a se ira hasta arriba en la lista , y como nosotros ya vamos en la letra d ya no se haran mas busquedas relacionadas a el nuevo subdominio a encontrado:

#cat -n agrega un  numero de renglon a cada linea del archivo , sort -uk2 indica que ordene y elimine duplicados a partir del segundo campo  es decir sin comtemplar el numero de renglon
#asignado, cuidado sin el k2 , movera los dominios alfabeticamente sin llevarse el renglon consigo ejemplo: 1 b , 2 a los ordenara asi : 1 a , 2 b , con el k2 los dejara asi 2 a , 1 b
#e aqui la clave, una vez quito  los repetidos y los dejo asi 2 a , 1 b , con sort -n le decimos que ordene por numero dejandolos 1b , 2a , es decir sin alterar su posicion original
#pero quitando las lineas repetidas , por ultimo con cut -f2- , quitamos el numero de renglon al txt.
cat -n $ruta/$objetivo-esubdomains.txt | sort -uk2 | sort -n | cut -f2- | tee $ruta/$objetivo-esubdomains-s.txt
#esta linea  evita perdida de datos , si intentas por ejemplo file.txt| sort -u  | tee file.txt el hacer  sort -u y sobreescribir el mismo archivo  a veces genera que se pierda mucha
#informacion, mas cuando son grandes cantidades de datos y se hace de forma repetitiva  como en este caso, cuando ves solo te quedan 2 lineas en tu .txt
#como puedes ver en la linea anterior ya que se quitaron las lineas repetidas y se pasaron a un nuevo archivo para evitar perdida, esta linea regresa la informacion de esubdomains-s
#a el archivo esubdomains.txt(que es el archivo original con el que se estara trabajando de forma repetida) sobreescribiendo su contenido.
cat $ruta/$objetivo-esubdomains-s.txt | tee $ruta/$objetivo-esubdomains.txt


#toma el archivo objetivo-esubdomains.txt y utiliza amass para encontrar mas objetivos

for subm in $(cat $ruta/$objetivo-esubdomains.txt);
do
amass enum -passive -d $subm | tee -a $ruta/$objetivo-esubdomains.txt;
#esta linea limpia el archivo objetivo-esubdomains.txt para evitar que se repitan subdominios en la lista y evitar un bucle infinito de busqueda -- linea aun a  prueba de como funciona
cat -n $ruta/$objetivo-esubdomains.txt | sort -uk2 | sort -n | cut -f2- | tee $ruta/$objetivo-esubdomains-s.txt
cat $ruta/$objetivo-esubdomains-s.txt | tee $ruta/$objetivo-esubdomains.txt
done
#eliminina esubdomains-s.txt para evitar hacer basura
rm $ruta/$objetivo-esubdomains-s.txt

#utiliza aquaton para extraer los subdominios 404
cat $ruta/$objetivo-esubdomains.txt | aquatone | grep "404" | tee -a $ruta/$objetivo-404subdoamins.txt

#realiza un analisis de posible subdomain take over
#la siguiente linea eliminia el indicador de error 404 a la lista de dominios con error 400 y la asigna como lista a recorrer por el for
for sto in $(cat $ruta/$objetivo-404subdoamins.txt | awk -F ": " '{print $1}');
do
# esta linea usa el comando dig CNAME en cada subdominio 404 para  seguir con las investigacion de posible subdomain take over , busca que en el resultado del comando haya
#un status: NXDOMAIN   lo guarda en una variable , un status NXDOMAIN es claro indicador de subdomain take over.
read=$(dig CNAME $sto | grep -o "status: NXDOMAIN")
#evalua si el resultado del comando anterior dio un satus: NXDOAMIN , y en caso de que sea asi ejecuta una serie de comandos que nos brindaran la informacion nesesaria para la explotacion
if [ "$read" = "status: NXDOMAIN" ];
then
# elimina el puerto y  el http de el subdominio para poder aplicar el comando host el cual nos dara la ip del objetivo y lo guarda en la variable host
Host=$(echo "$sto" | awk -F "http://" '{print $2}' | cut -f 1 -d ":")
#la siguiente linea ejecuta el comando host al subdominio y del resultado extrae solo iP y la ingresa en la variable ip
ip=$(host $Host | grep -E -o grep -E -o "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)")

#imprime la variable Host y ip , ademas de ejecutar el comando whois con la ip que obtuvimos y con grep solo extrae la organizacion en la cual se registro el dominio 
#la cual requerimos para ir a ella i intentar registar el subdominios y demostrar que existe un sudomain take over
echo "$Host $ip $(whois $ip | grep ""OrgName"") " | tee -a $ruta/$objetivo-subdomaintkver.txt
fi

done


