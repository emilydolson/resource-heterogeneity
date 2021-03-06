#Each row of the dataset provides statistics about an entire Avida population at a given time point 
#within a run of Avida.

#Replicate samples were collected by re-running Avida with the same configuration file and
# a different random seed.

#Start Code

#load libraries
library(car)
library(bbmle)
library(MASS)
library(arm)

######## Read in data ###################################################
dirs <- list.dirs(path = "../data/randomized_entropy", recursive=FALSE)

#Make sure that files from same replicate get merged appropriately
data <- NULL #This section adapted from stackoverflow.com answer
for (d in dirs) {
  phenotype_file_path <- paste(d, "phenotype_count.dat", sep = "/")
  task_file_path <- paste(d, "tasks.dat", sep = "/")
  if (file.exists(phenotype_file_path) & file.exists(task_file_path)){
    
    phenotypes <- read.csv(phenotype_file_path, header = F, sep = " ", na.strings = "", colClasses = "character", skip = 8)
    tasks <- read.csv(task_file_path, header = F, sep = " ", na.strings = "", colClasses = "character", skip = 15)
    tasks <- cbind(tasks[,1], tasks[,length(tasks)-1])
    
    dat <- merge(phenotypes, tasks, by = 1)
    
    dat$condition <- "randomized_entropy"
    dat$seed <- tail(unlist(strsplit(tail(unlist(strsplit(d, split = "/", fixed = T)), n=1), split="_", fixed=T))[3], n=1)
    data <- rbind(data, dat)
  }
}

ents <- read.csv("ents.csv", header = T, sep = ",")
data <- merge(data, ents, by = "seed")

#Remove Null columns
data$V7 <- NULL

#Assign column names
names(data)[2] <- "Updates"
names(data)[3] <- "PhenotypeRichness"
names(data)[4] <- "ShannonDiversityPhenotype"
names(data)[5] <- "PhenotypeRichnessbyTaskCount"
names(data)[6] <- "ShannonDiversityPhenotypeTaskCount"
names(data)[7] <- "AverageTaskDiversity"
names(data)[8] <- "EQU"

#Include factors as factors
data$condition<-factor(data$condition)

#Convert numeric type to numeric
data$seed <- as.numeric(data$seed)
data$Updates <- as.numeric(data$Updates)
data$PhenotypeRichness <- as.numeric(data$PhenotypeRichness)
data$ShannonDiversityPhenotype <- as.numeric(data$ShannonDiversityPhenotype)
data$PhenotypeRichnessbyTaskCount <- as.numeric(data$PhenotypeRichnessbyTaskCount)
data$ShannonDiversityPhenotypeTaskCount <- as.numeric(data$ShannonDiversityPhenotypeTaskCount)
data$AverageTaskDiversity <- as.numeric(data$AverageTaskDiversity)
data$EQU <- as.numeric(as.character(data$EQU))
data$ent <- as.numeric(data$ent)
data$overlap <- as.numeric(data$overlap)
data$functional_ent <- as.numeric(data$functional_ent)
data$variance <- as.numeric(data$variance)
data$kurtosis <- as.numeric(data$kurtosis)
data$skew <- as.numeric(data$skew)
data$resources <- as.numeric(data$resources)

#Take subset of data from end of run s
endPoints <- subset(data, (data$Updates==100000))

#Get diversities from before equals evolved
endPoints$preEQUdiv <- vector(mode="numeric", length=length(endPoints$seed))
for (s in unique(data$seed)){
  #print(seed)
  temp <- subset(data, (data$seed == s))
  #print(length(unique(temp$seed)))
  #print(temp$EQU[10000])
  for (i in order(temp$Updates)){
    if (temp$EQU[i] > 0){
      endPoints$preEQUdiv[endPoints$seed==s] <- temp$ShannonDiversityPhenotype[i-1]
      break()
    }
  } 
  if (endPoints$preEQUdiv[endPoints$seed==s] == 0){
    endPoints$preEQUdiv[endPoints$seed==s] <- temp$ShannonDiversityPhenotype[length(temp$ShannonDiversityPhenotype)]
  }
}

# We're about to make a bunch of models with interactions, so let's create centered versions of variables so that the interaction
# terms are meaningful:

endPoints$scaled_preEQUdiv <- scale(endPoints$preEQUdiv, scale = FALSE)
endPoints$scaled_overlap <- scale(endPoints$overlap, scale = FALSE)
endPoints$scaled_skew <- scale(endPoints$skew, scale = FALSE)
endPoints$scaled_kurtosis <- scale(endPoints$kurtosis, scale = FALSE)
endPoints$scaled_variance <- scale(endPoints$variance, scale = FALSE)
endPoints$scaled_ent <- scale(endPoints$ent, scale = FALSE)

endPoints$equ_evolved <- as.numeric(endPoints$EQU>0)

#Ian's ConditionNumber function
ConditionNumber <-function(mod){
  mod.X <- model.matrix(mod)
  eigen.x <- eigen(t(mod.X) %*%mod.X)
  eigen.x$val # eigenvalues from the design matrix
  sqrt(eigen.x$val[1]/eigen.x$val) # condition numbers
}

####### Analyze effect of entropy on diversity #################################################

ent_div_lm <- lm(ShannonDiversityPhenotype ~ ent, data=endPoints)
plot(ent_div_lm) #Woah, there's a definite outlier! Upon further investigation, it turns out that everything in that environment died.
#summary(ent_div_lm)

#try excluding outlier
ent_div_lm_outliers <- lm(ShannonDiversityPhenotype ~ ent, data=endPoints, subset=c(endPoints$seed!=50047))
plot(ent_div_lm_outliers) #Look okay, although there might be a slight curve in the residuals 
#summary(ent_div_lm_outliers) #didn't change substantially from original
                        #since there's a clear reason to exclude this point, it will be exclude from here on
hist(resid(ent_div_lm_outliers)) #looks good
acf(resid(ent_div_lm_outliers)) #looks good
qqnorm(resid(ent_div_lm_outliers)) #looks good
plot(endPoints$ShannonDiversityPhenotype[endPoints$seed!=50047], fitted(ent_div_lm_outliers))
abline(a=0,b=1) #There is a ton of scatter around this line, but that's okay. The goal is not to have the best
#prediction possible. It is to understand the effect of spatial heterogeneity on population diversity

confint(ent_div_lm_outliers)

plot(endPoints$ShannonDiversityPhenotype[endPoints$seed!=50047], fitted(ent_div_lm_outliers), xlab = "Standardized Phenotypic Shannon Diversity", ylab="Predicted Diversity")
abline(a=0,b=1)

# The outlier doesn't seem to have a huge effect, so we might as well leave it in
# There's another problem, though - populations that evolved EQU are capable of having higher diversity than those that didn't
# This will create problems when we're attempting to determine how factors impact evolution of EQU. So let's look at data from
# before EQU evolved.

# It turns out the effects are all roughly the same anyway. Here's the final model used in the paper:

final_div_lm <- lm(preEQUdiv ~ ent, data=endPoints)
plot(final_div_lm)
plot(endPoints$ent, resid(final_div_lm))
qqnorm(resid(final_div_lm))
summary(final_div_lm)
confint(final_div_lm)

setEPS()
cairo_ps("../figs/DiversityVsEntropy.eps", width = 4.2, height= 4.0)
showtext.begin()
ggplot(data=endPoints, aes(x=ent, y=preEQUdiv)) + 
  geom_point() + theme_classic(base_size = 12, base_family = "Arial") + 
  theme(axis.line.x = element_line(colour = "black"), axis.line.y = element_line(colour = "black"), legend.position="none") + 
  scale_x_continuous("Environmental Shannon entropy") + 
  scale_y_continuous("Phenotypic Shannon diversity") + geom_smooth(method=lm)
dev.off()

######### Predicting EQU evolution ###############################################################################

#Let's start with some diagnostics to make sure we're making valid models.

#Since we only care about predictors here, it's okay to just use a standard lm
diagnostic_lm = lm(EQU>0 ~ scaled_preEQUdiv+scaled_overlap+scaled_skew+scaled_kurtosis+scaled_variance, data=endPoints)
ConditionNumber(diagnostic_lm) #Not too bad
vif(diagnostic_lm) #Well, those are some pretty big numbers... And this is all centered, too
cov2cor(vcov(diagnostic_lm)) #looks like skew and kurtosis and mean (overlap) and variance are super colinear

#Let's just try mean and skew
diagnostic_lm = lm(EQU>0 ~ scaled_preEQUdiv+scaled_overlap+scaled_skew, data=endPoints)
ConditionNumber(diagnostic_lm) #Beautiful
vif(diagnostic_lm) #Much much better
cov2cor(vcov(diagnostic_lm)) #looks good

#How about variance and kurtosis?
diagnostic_lm = lm(EQU>0 ~ scaled_preEQUdiv+scaled_kurtosis+scaled_variance, data=endPoints)
ConditionNumber(diagnostic_lm) #great
vif(diagnostic_lm) #also great
cov2cor(vcov(diagnostic_lm))

#variance and skew?
diagnostic_lm = lm(EQU>0 ~ scaled_preEQUdiv+scaled_variance+scaled_skew, data=endPoints)
ConditionNumber(diagnostic_lm) 
vif(diagnostic_lm) 
cov2cor(vcov(diagnostic_lm)) #looks good

#Mean and kurtosis?
diagnostic_lm = lm(EQU>0 ~ scaled_preEQUdiv+scaled_overlap+scaled_kurtosis, data=endPoints)
ConditionNumber(diagnostic_lm) 
vif(diagnostic_lm) 
cov2cor(vcov(diagnostic_lm)) #looks good

#Okay, now we're going to add some interactions
diagnostic_lm = lm(EQU>0 ~ (scaled_preEQUdiv+scaled_overlap+scaled_skew)^3, data=endPoints)
ConditionNumber(diagnostic_lm) 
vif(diagnostic_lm) 
cov2cor(vcov(diagnostic_lm))
#even that is okay. Seems like we have eliminated to colinearity problem

# Negative log Likelihood calculator (Support function) from Ian's script
N <- 1

logistic.reg.fn.1 <- function(a, b1, b2, b3, b4) {
  p.pred <- plogis(a + b1*endPoints$scaled_preEQUdiv + b2*endPoints$scaled_overlap + b3*endPoints$scaled_skew +  b4*endPoints$scaled_skew*endPoints$scaled_overlap)
	-sum(dbinom((endPoints$EQU>0), size=N, prob=p.pred, log=T )) # We can plop this right into our NLL calculator.
}

#Let's try inluding interactions with diversity
logistic.reg.fn.2 <- function(a, b1, b2, b3, b4, b5, b6) {
  p.pred <- plogis(a + b1*endPoints$scaled_preEQUdiv + b2*endPoints$scaled_overlap + b3*endPoints$scaled_skew +  b4*endPoints$scaled_skew*endPoints$scaled_overlap + b5*endPoints$scaled_preEQUdiv*endPoints$scaled_overlap + b6*endPoints$scaled_preEQUdiv*endPoints$scaled_overlap)
  -sum(dbinom((endPoints$EQU>0), size=N, prob=p.pred, log=T )) # We can plop this right into our NLL calculator.
}

logistic.reg.fn.3 <- function(a, b1, b2, b3, b4) {
  p.pred <- plogis(a + b1*endPoints$scaled_preEQUdiv + b2*endPoints$scaled_variance + b3*endPoints$scaled_skew +  b4*endPoints$scaled_skew*endPoints$scaled_variance)
  -sum(dbinom((endPoints$EQU>0), size=N, prob=p.pred, log=T )) # We can plop this right into our NLL calculator.
}

logistic.reg.fn.4 <- function(a, b1, b2, b3, b4) {
  p.pred <- plogis(a + b1*endPoints$scaled_preEQUdiv + b2*endPoints$scaled_overlap + b3*endPoints$scaled_kurtosis +  b4*endPoints$scaled_kurtosis*endPoints$scaled_overlap)
  -sum(dbinom((endPoints$EQU>0), size=N, prob=p.pred, log=T )) # We can plop this right into our NLL calculator.
}

logistic.reg.fn.5 <- function(a, b1, b2, b3, b4) {
  p.pred <- plogis(a + b1*endPoints$scaled_preEQUdiv + b2*endPoints$scaled_variance + b3*endPoints$scaled_kurtosis +  b4*endPoints$scaled_variance*endPoints$scaled_kurtosis)
  -sum(dbinom((endPoints$EQU>0), size=N, prob=p.pred, log=T )) # We can plop this right into our NLL calculator.
}

#With no interaction?
logistic.reg.fn.6 <- function(a, b1, b2, b3) {
  p.pred <- plogis(a + b1*endPoints$scaled_preEQUdiv + b2*endPoints$scaled_variance + b3*endPoints$scaled_kurtosis)
  -sum(dbinom((endPoints$EQU>0), size=N, prob=p.pred, log=T )) # We can plop this right into our NLL calculator.
}

log.reg.optim.function1 <- mle2(logistic.reg.fn.1, start=list(a=0.5,b1=0.1, b2=.1, b3=.1, b4=.1))
profile.log.regfunction1 <- profile(log.reg.optim.function1)
plot(profile.log.regfunction1) #looks great
#summary(log.reg.optim.function1)

#Try it again with different starting values, just to be safe
log.reg.optim.function1 <- mle2(logistic.reg.fn.1, start=list(a=0.5,b1=0.1, b2=.5, b3=.8, b4=.3))
profile.log.regfunction1 <- profile(log.reg.optim.function1)
plot(profile.log.regfunction1) #looks exactly the same! Awesome.
#summary(log.reg.optim.function1)

#Try it with one last set of different starting values
log.reg.optim.function1 <- mle2(logistic.reg.fn.1, start=list(a=1,b1=1, b2=1, b3=1, b4=1))
profile.log.reg3 <- profile(log.reg.optim.function1)
plot(profile.log.regfunction1) #Still the same. Seems solid.
#summary(log.reg.optim.function1)


#Try it with the diversity interaction
#log.reg.optim.function2 <- mle2(logistic.reg.fn.2, start=list(a=0.2,b1=1.7, b2=1.4, b3=.99, b4=.39, b5=.4, b6=.7))
#Didn't converge
#log.reg.optim.function2 <- mle2(logistic.reg.fn.2, start=list(a=0.2,b1=1.7, b2=1.4, b3=.99, b4=.39, b5=1, b6=.3))
#Didn't converge
#log.reg.optim.function2 <- mle2(logistic.reg.fn.2, start=list(a=0.2,b1=1.7, b2=1.4, b3=.99, b4=.39, b5=.4, b6=.7),method = "Nelder-Mead") #Okay at least that converged... 
#profile.log.regfunction2 <- profile(log.reg.optim.function2) #but the profiles for the interactions with diversity are pretty awful
#log.reg.optim.function2 <- mle2(logistic.reg.fn.2, start=list(a=0.2,b1=1.7, b2=1.4, b3=.99, b4=.39, b5=.4, b6=.7),method = "BFGS") #woo that converged too... 
#profile.log.regfunction2 <- profile(log.reg.optim.function2) #but the profiles for the interactions with diversity are pretty awful
#After playing with different starting values and optimizers, there seems to be very little confidence attainable about interactions with diversity. This model will be ommitted.
#plot(profile.log.regfunction2)
#summary(log.reg.optim.function2)
#(commented out because some of these sometimes don't converge)

#Okay, let's try the other mean, skew, variance, and kurtosis models:
log.reg.optim.function3 <- mle2(logistic.reg.fn.3, start=list(a=1,b1=1, b2=1, b3=1, b4=1))
profile.log.regfunction3 <- profile(log.reg.optim.function3)
plot(profile.log.regfunction3) #Looks good.
#summary(log.reg.optim.function3)

log.reg.optim.function4 <- mle2(logistic.reg.fn.4, start=list(a=1,b1=1, b2=1, b3=1, b4=1))
profile.log.regfunction4 <- profile(log.reg.optim.function4)
plot(profile.log.regfunction4) #Looks solid.
#summary(log.reg.optim.function4)

log.reg.optim.function5 <- mle2(logistic.reg.fn.5, start=list(a=1,b1=1, b2=1, b3=1, b4=1))
profile.log.regfunction5 <- profile(log.reg.optim.function3)
plot(profile.log.regfunction5) #Looking good.
#summary(log.reg.optim.function5)

log.reg.optim.function6 <- mle2(logistic.reg.fn.6, start=list(a=1,b1=1, b2=1, b3=1))
profile.log.regfunction6 <- profile(log.reg.optim.function6)
plot(profile.log.regfunction5) #Looking good.
#summary(log.reg.optim.function5)

#Now use AIC to compare: (note: these values are from the preliminary data that were used for model selection - 
# they may be slightly different with the final data-set)
#AIC(log.reg.optim.function1) #479.75 -> delta = 0
#AIC(log.reg.optim.function3) #494.44 -> delta = 16.69
#AIC(log.reg.optim.function4) #481.12 -> delta = 1.37
#AIC(log.reg.optim.function5) #502.10 -> delta = 22.35
#AIC(log.reg.optim.function6) #504.24 -> delta = 24.49

best = 479.75
total = 0.0
for (delta in c(0, 16.69, 1.37, 22.35, 24.49)){ total = total + exp(-.5*(delta))}
AkaikeWeight <- function(delta){
  exp(-.5*(delta))/total
}
#for (delta in c(0, 16.69, 1.37, 22.35, 24.49)) {print(AkaikeWeight(delta))}
# 0.6647404
# 0.00015793
# 0.3350891
# 9.3199e-06
# 3.196805e-06
#There are two models with non-negligible support: 1 (overlap and skew) and 4 (overlap and kurtosis).

#Now lets do this with glm to make sure results are the same
meankurtosis.glm <- glm(EQU>0 ~ scaled_preEQUdiv+(scaled_overlap+scaled_kurtosis)^2, family=binomial(link="logit"), data=endPoints)
summary(meankurtosis.glm) #Still the same! Great! Also the residual deviance looks okay.
vcov(meankurtosis.glm)

meanskew.glm <- glm(equ_evolved ~ scaled_preEQUdiv*scaled_overlap*scaled_skew, family=binomial(link="logit"), data=endPoints)
summary(meanskew.glm) #Looks good!
#These results are qualitatively similar, but not identical. However, there isn't a logical way to average them together, given that they contain such different variables and contain variables that are colinear with each other.
vcov(meanskew.glm)

#McFadden's pseudo R-squared:
1-meankurtosis.glm$deviance/meankurtosis.glm$null.deviance
1-meanskew.glm$deviance/meanskew.glm$null.deviance # This one is a little better (~.15 vs .11)

#Make model with entropy instead of diversity to try to untangle the effect of heterogeneity on evolvability from the effect of diversity:
logistic.reg.fn.7 <- function(a, b1, b2, b3, b4) {
  p.pred <- plogis(a + b1*endPoints$scaled_ent + b2*endPoints$scaled_overlap + b3*endPoints$scaled_kurtosis + b4*endPoints$scaled_kurtosis*endPoints$scaled_overlap)
  -sum(dbinom((endPoints$EQU>0), size=N, prob=p.pred, log=T )) # We can plop this right into our NLL calculator.
}

log.reg.optim.function7 <- mle2(logistic.reg.fn.7, start=list(a=1,b1=1, b2=1, b3=1, b4=1))
profile.log.regfunction7 <- profile(log.reg.optim.function7)
plot(profile.log.regfunction7) #seems fine
#summary(log.reg.optim.function4)
ent.glm <- glm(EQU>0 ~ ent+(overlap+skew)^2, family=binomial(link="logit"), data=endPoints)
summary(ent.glm)
AIC(ent.glm)

# Let's take a look at the models
plot(endPoints$ShannonDiversityPhenotype, endPoints$EQU>0, xlab="Phenotypic Shannon Diversity", ylab="Equals evolved?")
curve( plogis(coef(meanskew.glm)[1] + coef(meanskew.glm)[2]*x), -3, 6, ylab= "Prob of evolving equals", lwd=5,add=T, col="blue")
curve( plogis(coef(meankurtosis.glm)[1] + coef(meankurtosis.glm)[2]*x), -3, 6, ylab= "Prob of evolving equals", lwd=5,add=T, col="red") 
coefplot(meanskew.glm, varnames=c("intercept", "diversity", "mean", "skew"), mar=c(0,5,5,0))
coefplot(meankurtosis.glm, varnames=c("intercept", "diversity", "mean", "kurtosis", "mean*kurtosis"), mar=c(0,5,5,0))

# Since the fit seems pretty equivalent and skew is easier to understand than kurtosis, we'll go with skew.

summary(meanskew.glm)
confint(meanskew.glm)

# Make sure that overlap*skew is actually capturing all of the information that entropy captures.

ent_pred_lm <- lm(ent ~ overlap*skew, data=endPoints)
summary(ent_pred_lm)
plot(ent_pred_lm)
qqnorm(resid(ent_pred_lm))
plot(endPoints$ent, resid(ent_pred_lm))
confint(ent_pred_lm)
coefplot(ent_pred_lm)

#Looks like it is!