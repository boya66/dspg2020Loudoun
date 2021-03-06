#LOUDOUN COUNTY FOOD INSECURITY

setwd("~/dspg2020Loudon")

library(tidycensus)
library(tidyverse)
library (stringr)
library(ggplot2)
library(olsrr)
library(stats)
library(psych)
library(viridis)
library(ggthemes)
library(ggmap)
library(ggspatial)
library(sf)

# Potential variable tables for predicting food insecurity (from FeedingAmerica):
# B14006 (non- undergraduate student poverty rate), 
# C17002 (ratio of income to poverty level), 
# B19013 (median income), 
# DP04 (homeownership rate), 
# DP05 (percent African American and percent Hispanic)
# S1810 (disability rate)
# S2301 (Unemployment)

#show available variables in a particular ACS survey
acs5<-load_variables(2009, "acs5", cache=T)
View(acs5)

acs5_subject <- load_variables(2018, "acs5/subject", cache=T)
View(acs5_subject)

acs5_profile<- load_variables(2018, "acs5/profile", cache=T)
View(acs5_profile)

#FUNCTIONS:

# 1. "acs_tables" calls "get_acs" (from tidycensus) on a vector of table names. It returns a dataframe of 
# all the tables bound together.  The function requires a vector of table names, 
# a census API key, and a geographical unit.  The user can add other parameters as well.

acs_tables<-function(tables,key,geography,...){
  acs_data<-NULL
  for(i in 1:length(tables)){
    data<-get_acs(geography = geography,
                  table = tables[i],
                  key = key,
                  show_call = T,
                  cache_table=T,
                  ...
    )
    acs_data<-rbind(acs_data,data.frame(data))
  }
  return(acs_data)
}

# 2. "acs_wide" cleans the data returned from a census API call.  More specifically, 
# it separates the variable column into separate variables, and it separates "NAME" into 
# different columns with pre-defined column names (NAME_col_names). The function also
# drops the "margin of error" column.

acs_wide<-function(data,NAME_col_names){
  data%>%
    select (-moe)%>%
    pivot_wider(names_from = variable,values_from=estimate)%>%
    separate(NAME, into=NAME_col_names, sep = ", ")
}


#3. acs_years retrieves individual variables (or a list of variables) across a series of years.
acs_years<-function(years,key,geography,...){
  acs_data<-NULL
  for(i in 1:length(years)){
    acs<-get_acs(geography = geography,
                 #variables = vars,
                 key = key,
                 year=years[i],
                 output = "wide",
                 show_call = T,
                 geometry = F,
                 ...)
    acs_data<-(rbind(acs_data,data.frame(acs)))
  }
  acs_data<-cbind(acs_data,year=rep((years),each=length(unique(acs_data$GEOID))))
  return(acs_data)
}


#4. "acs_years_tables" uses two previously defined functions (acs_tables and acs_wide) to return multiple 
# variable tables across multiple years in one single tibble.  A couple of notes: the way that 
# get_acs handles variables before 2013 varies, so this function only works for 2013 and after.
# For variable tables before 2013, use acs_tables to pull individual sets of tables.  Also, I have 
# not included "geometry" in the function.  If the user includes geometry, he/she may need 
# to modify the call to acs_wide.


acs_years_tables<-function(tables,years,key,geography,NAME_col_names,...){
  acs_data<-NULL
  for (j in 1:length(years)){
    acs<-acs_tables(tables=tables,year=years[j],key=key,geography = geography,...)
    year<-rep(years[j],times=length(acs$GEOID))
    acs_years2<-cbind(year,data.frame(acs))
    acs_data<-(rbind(acs_data,acs_years2))
  }
  acs_data<-acs_wide(acs_data,NAME_col_names = NAME_col_names)
  return(acs_data)
}

#NATIONAL AND LOUDOUN DATA

tables<-c("B14006","C17002","B19013","DP04","DP05","S1810","S2301")
years<-c(2013,2014,2015,2016,2017,2018)
colnames=c("Census_tract","County","State")

acs_Loudon<-acs_years_tables(tables=tables,
                             years=years,
                             key=.key,
                             geography="tract",
                             state="VA",
                             county="Loudoun",
                             NAME_col_names = colnames)

acs_NoVa<-acs_years_tables(tables=tables,
                             years=years,
                             key=.key,
                             geography="tract",
                             state="VA",
                             county=c("Arlington county",
                                      "Fairfax county",
                                      "Loudoun county",
                                      "Prince William county",
                                      "Alexandria city",
                                      "Falls Church city",
                                      "Fairfax city",
                                      "Manassas city",
                                      "Manassas Park city",
                                      "Fauquier county"),
                             NAME_col_names = colnames)
colnames="state"
acs_state<-acs_years_tables(tables = tables,
                            key = .key,
                            geography = "state",
                            years=years,
                            NAME_col_names = colnames)


#The following code pulls in CPS food security data downloaded using IPUMS
cps_00002 <- read.csv("~/Desktop/cps_00002.csv")
cps<-cps_00002%>%
  select(YEAR,CPSID,STATEFIP,FSSTATUS,FSSTATUSD)%>%
  filter(!is.na(FSSTATUSD))%>%
  filter(!FSSTATUSD %in% c(99,98))

# I estimate a state's food insecurity level taking the ratio of households
# that score 3 or 4 on the food insecurity survey to all households surveyed.  

#Clean CPS food insecurity data
FSbyState<-cps%>%
  mutate(LowSecurity=FSSTATUSD%in%c(3,4))%>%
  group_by(STATEFIP,YEAR)%>%
  summarize(InsecurityRate=mean(LowSecurity)*100)%>%
  filter(YEAR>=2013)

#Clean national data
acs_state_clean<-acs_state%>%
  filter(GEOID!=72)%>%
  arrange(year)%>%
  arrange(GEOID)%>%
  rename(STATEFIP=GEOID)%>%
  rename(YEAR=year)
acs_state_clean$STATEFIP=as.integer(acs_state_clean$STATEFIP)

#Join ACS and CPS food insecurity data
acs_state_insecurity<-inner_join(acs_state_clean,FSbyState,by=c("STATEFIP", "YEAR"))

#Calculate relevant variables to be used in the linear model
acs_state_insecurity<-acs_state_insecurity%>%
  mutate(PovertyRate=((B14006_002-(B14006_009+B14006_010))/B14006_001)*100)%>%
  mutate(MedianIncome=B19013_001)%>%
  mutate(OwnRate=(DP04_0046P))%>%
  mutate(PerAfAm=(DP05_0038P))%>%
  mutate(PerHisp=(DP05_0071P))%>%
  mutate(DisRate=(S1810_C03_001))%>%
  mutate(Unemployment=S2301_C04_021)

#Construct linear model with year and state as fixed effects
Model<-lm(log(InsecurityRate)~PovertyRate+MedianIncome+OwnRate+PerAfAm+PerHisp+
            DisRate+Unemployment+as.factor(YEAR)+as.factor(STATEFIP)-1,data=acs_state_insecurity)
summary(Model)

#Plot residuals v. fitted values to test for heteroscedasticity
ols_plot_resid_fit(Model)


#Calculate mdoel variables for Loudoun County
acs_Loudon_insecurity<-acs_Loudon%>%
  mutate(PovertyRate=((B14006_002-(B14006_009+B14006_010))/B14006_001)*100)%>%
  mutate(MedianIncome=B19013_001)%>%
  mutate(OwnRate=(DP04_0046P))%>%
  mutate(PerAfAm=(DP05_0038P))%>%
  mutate(PerHisp=(DP05_0071P))%>%
  mutate(DisRate=(S1810_C03_001))%>%
  mutate(Unemployment=S2301_C04_021)

LoudounReduced<-acs_Loudon_insecurity%>%
  select(GEOID,year, Census_tract, County, State, PovertyRate, MedianIncome, OwnRate, PerAfAm, PerHisp, DisRate,Unemployment)%>%
  rename(YEAR=year)

LoudounReduced$STATEFIP<-as.integer(rep(51,times=length(LoudounReduced$GEOID)))
LoudounReduced<-as.data.frame(LoudounReduced)

#Make predictions for Loudoun County based on national model.
LoudounFoodInsecurity<-c()
for(i in 1:length(LoudounReduced$PovertyRate))
{
  p<-predict(Model,newdata = LoudounReduced[i,])
  LoudounFoodInsecurity[i]<-p
}

LoudounReduced<-cbind(LoudounReduced,LoudounFoodInsecurity)

#Calculate model variables for NoVa
acs_NoVa_insecurity<-acs_NoVa%>%
  mutate(PovertyRate=((B14006_002-(B14006_009+B14006_010))/B14006_001)*100)%>%
  mutate(MedianIncome=B19013_001)%>%
  mutate(OwnRate=(DP04_0046P))%>%
  mutate(PerAfAm=(DP05_0038P))%>%
  mutate(PerHisp=DP05_0071P)%>%
  mutate(DisRate=(S1810_C03_001))%>%
  mutate(Unemployment=S2301_C04_021)

NoVaReduced<-acs_NoVa_insecurity%>%
  select(GEOID,year, Census_tract, County, State, PovertyRate, MedianIncome, OwnRate, PerAfAm, PerHisp, DisRate,Unemployment)%>%
  rename(YEAR=year)

NoVaReduced$STATEFIP<-as.integer(rep(51,times=length(NoVaReduced$GEOID)))
NoVaReduced<-as.data.frame(NoVaReduced)

#Make predictions for NoVa based on national model.
NoVaFoodInsecurity<-c()
for(i in 1:length(NoVaReduced$PovertyRate))
{
  p<-predict(Model,newdata = NoVaReduced[i,])
  NoVaFoodInsecurity[i]<-p
}

NoVaReduced<-cbind(NoVaReduced,NoVaFoodInsecurity)



#MAPPING

#Get geometry data for Loudoun County
LoudounGeometry<-get_acs(geography = "tract",
                             state="VA",
                             county = "Loudoun",
                             variables = "B19058_002",
                             survey = "acs5",
                             key = .key,
                             year=2018,
                             output = "wide",
                             show_call = T,
                             geometry = T,
                             keep_geo_vars = T)%>%
  select(-c(11:12))

# Join geometry data to food insecurity predictions and filter data by a particular year
LoudounReducedGeom<-inner_join(LoudounReduced,LoudounGeometry,by="GEOID")%>%
  mutate(expFoodInsecurity=exp(LoudounFoodInsecurity))%>%
  filter(YEAR==2018)

#Divide Food Insecurity data for Loudon into Quantiles
quantile.interval = quantile(LoudounReducedGeom$LoudounFoodInsecurity, probs=seq(0, 1, by = .2),na.rm = T)
LoudounReducedGeom$LoudounFoodInsecurityQuan = cut(LoudounReducedGeom$LoudounFoodInsecurity, breaks=quantile.interval, include.lowest = TRUE)
LoudounReducedGeom$LoudounFoodInsecurityQuan<-as.factor(LoudounReducedGeom$LoudounFoodInsecurityQuan)

# Plot Loudoun

#get ggmap
ggmap::register_google(key = .key2)
map <- get_googlemap(center = c(lon = -77.638057, lat = 39.108329),maptype = "roadmap")

#add geom_sf to ggmap
ggmap(map)+
  geom_sf(data=LoudounReducedGeom,inherit.aes=F,aes(geometry=geometry,fill = LoudounFoodInsecurityQuan,color = LoudounFoodInsecurityQuan),show.legend = "fill") +
  geom_sf(data=va_sf%>%filter(COUNTYFP==107),inherit.aes=F,fill="transparent",color="black",size=0.5)+
  labs(title="Loudoun County",subtitle="2018 Food Insecurity Rate")+
  scale_fill_viridis(discrete=T,name = "Quantiles", labels = c("1","2","3","4","5"),guide = guide_legend(reverse=TRUE))+
  scale_color_viridis(discrete=T,name = "Quantiles", labels = c("1","2","3","4","5"),guide = guide_legend(reverse=TRUE))+
  theme_map()+
  theme(legend.position=c(0.905,0.79))

                        
#Get geometry data for NoVa census tracts
NoVaGeometry<-get_acs(geography = "tract",
                         state="VA",
                         county=c("Arlington county",
                                  "Fairfax county",
                                  "Loudoun county",
                                  "Prince William county",
                                  "Alexandria city",
                                  "Falls Church city",
                                  "Fairfax city",
                                  "Manassas city",
                                  "Manassas Park city",
                                  "Fauquier county"),
                         variables = "B19058_002",
                         survey = "acs5",
                         key = .key,
                         year=2018,
                         output = "wide",
                         show_call = T,
                         geometry = T,
                         keep_geo_vars = T)%>%
  select(-c(11:12))

# Join geometry data to food insecurity predictions and filter data by a particular year
NoVaReducedGeom<-NoVaReduced%>%
  filter(YEAR==2018)%>%
  inner_join(NoVaGeometry,by="GEOID")%>%
  mutate(expFoodInsecurity=exp(NoVaFoodInsecurity))

# There are two census tracts with very high food insecurity rates.  For the purposes 
# of visualization and differentiation between tracts, I'm capping the rate at 4 (log scale),
# which is equivalent to 60% food insecrity
#NoVaReducedGeom[c(172,493),14]<-4

#Get county outlines for NoVa
va_sf<-get_acs(geography = "county",
                      state="VA",
                      county=c("Arlington county",
                               "Fairfax county",
                               "Loudoun county",
                               "Prince William county",
                               "Alexandria city",
                               "Falls Church city",
                               "Fairfax city",
                               "Manassas city",
                               "Manassas Park city",
                               "Fauquier county"),
                      variables = "B19058_002",
                      survey = "acs5",
                      key = .key,
                      year=2018,
                      output = "wide",
                      show_call = T,
                      geometry = T,
                      keep_geo_vars = T)%>%
  select(COUNTYFP,geometry)

#Divide Food Insecurity data for Loudon into Quantiles
quantile.interval = quantile(NoVaReducedGeom$NoVaFoodInsecurity, probs=seq(0, 1, by = .2),na.rm = T)
NoVaReducedGeom$NoVaFoodInsecurityQuan = cut(NoVaReducedGeom$NoVaFoodInsecurity, breaks=quantile.interval, include.lowest = TRUE)

#Put NAs in quantile 1
NoVaReducedGeom$NoVaFoodInsecurityQuan[is.na(NoVaReducedGeom$NoVaFoodInsecurityQuan)]<-"[0.195,1.53]"


# Plot NoVa
map2 <- get_googlemap(center = c(lon = -77.543986, lat = 38.858802),zoom=9, maptype = "roadmap")

ggmap(map2) 

ggplot()+
  geom_sf(data=NoVaReducedGeom,inherit.aes=F,aes(geometry=geometry,fill = NoVaFoodInsecurityQuan, color = NoVaFoodInsecurityQuan),show.legend = "fill") +
  geom_sf(data=va_sf,inherit.aes=F,fill="transparent",color="black",size=0.5)+
  geom_sf(data=va_sf%>%filter(COUNTYFP==107),fill="transparent",color="red",size=0.7,show.legend = F)+
  labs(title="Northern Virginia",subtitle="2018 Food Insecurity Rate")+
  scale_fill_viridis(discrete=T,name = "Quantiles", labels = c("1","2","3","4","5"),guide = guide_legend(reverse=TRUE))+
  scale_color_viridis(discrete=T,name = "Quantiles", labels = c("1","2","3","4","5"),guide = guide_legend(reverse=TRUE))


