#!/usr/local/bin/perl



#parametre
$long_min=  21;    # longueur minimale d'un pre-miARN
$long_max=   300;	#longueur maximale d'un pre-miARN
$nb_min_app= 7;	#nombre minimum d'appariement dans la tige 


#variables
%BP=();
$fin_tige = 0; #variable bool�enne (initialis� � 0)
$nb_app = 0;#nombre d'appariements de la tige en cours (initialis� � 0)
$position_debut=0;#position de d�but de la tige qu'on est en train de construire (intialis� � 0)
$derniere_position=0;#position de la base 3' impliqu�e dans le dernier appariement utilis� (initialis� � 0)

my ($CT) = @ARGV;
open(FOut, $CT) || die "Probl�me � l\'ouverture : $!"; #ouverture du fichier de sortie de RNAFOLD
while(my $line = <FOut>)
{       
	my @variable = split('\s+', $line);
	if (@variable[2]=~ /^ENERGY/)
	{       
		$longueur = @variable[1]; 
		$nomSeq = substr @variable[5], 0; # R�cup�ration du nom de la s�quence
		
	} 
	else
	{
		$BP{@variable[1]} = @variable[5];
		$colonne5 = @variable[5];
		#print @variable[1];print @variable[5]; 
		if ($longueur == @variable[1]) # tester si la longueur actuelle est �gale � la longueur de la s�quence
		{       
			#print $longueur;
		      
		}
	}
}  



for ($i = 1; $i<=$longueur ; $i++ )
{
	if ($nb_app == O)
	{
		
	 	# on regarde si on peut d�marrer une nouvelle tige
		if (($long_min <= $BP{$i}-$i+1) &&($long_max >= $BP{$i}-$i+1) )
     		{ 	
			# on d�marre une nouvelle tige
			$nb_app=1;  
			$position_debut=$i; 
			$derniere_position= $BP{$i};
     		}
 	}
	else # on sait que nb_app > 0  
	{
		#On a trois cas.
		# cas 1: BP[i]= 0. La base i est libre. On ne fait rien.
		if ($BP{$i}==0)
		{
		}
		if ($BP{$i}<$i)#cas 2: BP[i]< i. On est en train de parcourir le deuxi�me brin de la tige. 
		{
			if ($nb_app >= $nb_min_app)
			{
				print "position_debut:".$position_debut; print "position_fin:". $BP{$position_debut};
				$nb_app = 0;
			}
		}		
		
		if ($i<$BP{$i})#cas 3:  On est sur la position 5' d'un appariement.  On regarde si on est toujours dans la m�me tige,  ou si c'est le d�but d'une nouvelle tige. 
		{
			if ($derniere_position-$BP{$i}>6)
			{
				for ($j = $BP{$i}+1,$j <=$derniere_position, $j++)
				{
					if ($BP{$i} != 0) # c'est la fin de la tige
					{
						$fin_tige = 1;
					}
				}
			}
			if ($fin_tige ==0) # on �tend la tige
			{	   
				$derniere_position=$BP{$i}; 
				$nb_app=$nb_app+1; 
			}
			else
			{
				$fin_tige = 0;
				if ($nb_app >= $nb_min_app)
				{
					print "position_debut:".$position_debut; print "position_fin:". $BP{$position_debut};
				}
				#on regarde si on peut d�marrer une nouvelle tige
				if (($long_min <= $BP{$i}-$i+1) &&($long_max >= $BP{$i}-$i+1))
				{
					#on d�marre une nouvelle tige
					$nb_app=1;  
					$position_debut=$i; 
					$derniere_position= $BP{$i};
					
				}
			}
		}
	}
}
